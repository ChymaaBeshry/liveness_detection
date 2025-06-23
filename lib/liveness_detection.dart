// باقي الـ imports كما هي
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:camera/camera.dart';

enum LivenessChallenge {
  smile,
  blink,
  rightEyeWink,
  leftEyeWink,
  turnHeadLeft,
  turnHeadRight,
}

class PassiveLivenessPage extends StatefulWidget {
  const PassiveLivenessPage({super.key});

  @override
  _PassiveLivenessPageState createState() => _PassiveLivenessPageState();
}

class _PassiveLivenessPageState extends State<PassiveLivenessPage> {
  final FaceDetector faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableClassification: true,
      minFaceSize: 0.3,
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  late CameraController cameraController;
  bool isCameraInitialized = false;
  bool isDetecting = false;

  double? smilingProbability;
  double? leftEyeOpenProbability;
  double? rightEyeOpenProbability;
  double? headEulerAngleY;

  bool isVerifying = false;
  bool verificationComplete = false;
  bool verificationPassed = false;
  DateTime? verificationStartTime;

  bool isFaceCentered = false;
  int failedAttempts = 0;

  bool challengeMode = false;
  LivenessChallenge? selectedChallenge;
  bool challengePassed = false;

  double? _initialLeftEye;
  double? _initialRightEye;
  double? _initialHeadY;
  double? _initialSmile;

  List<double> smileList = [];
  List<double> leftEyeList = [];
  List<double> rightEyeList = [];
  List<double> headYList = [];

  @override
  void initState() {
    super.initState();
    initializeCamera();
  }

  Future<void> initializeCamera() async {
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
    );
    cameraController = CameraController(
      frontCamera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    await cameraController.initialize();
    if (mounted) {
      setState(() => isCameraInitialized = true);
      startFaceDetection();
    }
  }

  void startFaceDetection() {
    if (isCameraInitialized) {
      cameraController.startImageStream((CameraImage image) {
        if (!isDetecting) {
          isDetecting = true;
          detectFaces(image).then((_) => isDetecting = false);
        }
      });
    }
  }

  bool hasSignificantTemporalVariation(List<double> list) {
    if (list.length < 5) return false;
    int significantChanges = 0;
    for (int i = 1; i < list.length; i++) {
      double diff = (list[i] - list[i - 1]).abs();
      if (diff > 0.05) {
        significantChanges++;
      }
    }
    return significantChanges >= 4;
  }

  bool hasVariation(List<double> list) {
    return hasSignificantTemporalVariation(list);
  }

  LivenessChallenge getRandomChallenge() {
    final random = math.Random();
    return LivenessChallenge.values[random.nextInt(
      LivenessChallenge.values.length,
    )];
  }

  bool passedLivenessConditions(
    List<double> leftEye,
    List<double> rightEye,
    List<double> smile,
    List<double> headY,
  ) {
    final eyeMoved = hasVariation(leftEye) || hasVariation(rightEye);
    final smileChanged = hasVariation(smile);
    final headMoved = hasVariation(headY);

    final passedConditions =
        [eyeMoved, smileChanged, headMoved].where((v) => v).length;
    return passedConditions >=
        2; // 🔒 الآن مطلوب تحقق من شرطين على الأقل بدلًا من واحد فقط
  }

  Future<void> detectFaces(CameraImage image) async {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotation.rotation270deg,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      final faces = await faceDetector.processImage(inputImage);
      if (!mounted) return;

      if (faces.isNotEmpty) {
        final face = faces.first;
        final screenSize = MediaQuery.of(context).size;
        final centered = isFaceInsideCircle(face, screenSize);

        setState(() {
          smilingProbability = face.smilingProbability;
          leftEyeOpenProbability = face.leftEyeOpenProbability;
          rightEyeOpenProbability = face.rightEyeOpenProbability;
          headEulerAngleY = face.headEulerAngleY;
          isFaceCentered = centered;
        });

        if (!isFaceCentered) return;

        if (challengeMode && selectedChallenge != null && !challengePassed) {
          if (_initialLeftEye == null &&
              _initialRightEye == null &&
              _initialHeadY == null &&
              _initialSmile == null) {
            _initialLeftEye = face.leftEyeOpenProbability ?? 0;
            _initialRightEye = face.rightEyeOpenProbability ?? 0;
            _initialHeadY = face.headEulerAngleY ?? 0;
            _initialSmile = face.smilingProbability ?? 0;
            verificationStartTime = DateTime.now();
          }

          final elapsed =
              DateTime.now().difference(verificationStartTime!).inSeconds;
          if (elapsed >= 5) {
            Navigator.pop(context, null);
            return;
          }

          switch (selectedChallenge!) {
            case LivenessChallenge.blink:
              final left = face.leftEyeOpenProbability ?? 0;
              final right = face.rightEyeOpenProbability ?? 0;
              if ((left < 0.3 || right < 0.3) &&
                  (_initialLeftEye! > 0.6 && _initialRightEye! > 0.6)) {
                challengePassed = true;
              }
              break;
            case LivenessChallenge.turnHeadLeft:
              if ((_initialHeadY ?? 0) - (face.headEulerAngleY ?? 0) > 10) {
                challengePassed = true;
              }
              break;
            case LivenessChallenge.turnHeadRight:
              if ((face.headEulerAngleY ?? 0) - (_initialHeadY ?? 0) > 10) {
                challengePassed = true;
              }
              break;
            case LivenessChallenge.smile:
              if ((face.smilingProbability ?? 0) > 0.7 &&
                  (_initialSmile != null &&
                      (_initialSmile! - (face.smilingProbability ?? 0)).abs() >
                          0.2)) {
                challengePassed = true;
              }
              break;
            case LivenessChallenge.rightEyeWink:
              if ((_initialRightEye ?? 1.0) > 0.5 &&
                  (face.rightEyeOpenProbability ?? 1.0) < 0.3) {
                challengePassed = true;
              }
              break;
            case LivenessChallenge.leftEyeWink:
              if ((_initialLeftEye ?? 1.0) > 0.5 &&
                  (face.leftEyeOpenProbability ?? 1.0) < 0.3) {
                challengePassed = true;
              }
              break;
          }

          if (challengePassed) {
            final file = await captureAndReturnImage();
            if (mounted) Navigator.pop(context, file);
          }

          return;
        }

        if (!isVerifying && !verificationComplete) {
          isVerifying = true;
          verificationStartTime = DateTime.now();
          smileList.clear();
          leftEyeList.clear();
          rightEyeList.clear();
          headYList.clear();
        }

        if (isVerifying && !verificationComplete) {
          smileList.add(face.smilingProbability ?? 0);
          leftEyeList.add(face.leftEyeOpenProbability ?? 0);
          rightEyeList.add(face.rightEyeOpenProbability ?? 0);
          headYList.add(face.headEulerAngleY ?? 0);

          final elapsed =
              DateTime.now().difference(verificationStartTime!).inSeconds;
          if (elapsed >= 5) {
            isVerifying = false;
            verificationComplete = true;

            final eyeMoved =
                hasVariation(leftEyeList) || hasVariation(rightEyeList);
            final smileChanged = hasVariation(smileList);
            final headMoved = hasVariation(headYList);

            final passedConditions =
                [eyeMoved, smileChanged, headMoved].where((v) => v).length;
            verificationPassed = passedConditions >= 2;

            debugPrint(
              'Eye moved: \$eyeMoved, Smile changed: \$smileChanged, Head moved: \$headMoved',
            );

            setState(() {});
            await Future.delayed(const Duration(seconds: 1));

            if (verificationPassed) {
              final file = await captureAndReturnImage();
              if (mounted) Navigator.pop(context, file);
            } else {
              failedAttempts++;
              if (failedAttempts >= 3) {
                challengeMode = true;
                selectedChallenge = getRandomChallenge();
                challengePassed = false;
                _initialLeftEye = null;
                _initialRightEye = null;
                _initialHeadY = null;
                _initialSmile = null;
                verificationStartTime = DateTime.now();
                setState(() {});
              } else {
                await Future.delayed(const Duration(seconds: 1));
                setState(() {
                  verificationComplete = false;
                  isVerifying = false;
                });
              }
            }
          }
        }
      } else {
        setState(() => isFaceCentered = false);
      }
    } catch (e) {
      debugPrint('Error in face detection: \$e');
    }
  }

  bool hasGradualMovement(List<double> list) {
    if (list.length < 5) return false;
    double totalMovement = 0;
    for (int i = 1; i < list.length; i++) {
      totalMovement += (list[i] - list[i - 1]).abs();
    }
    return totalMovement > 0.2;
  }

  Future<File?> captureAndReturnImage() async {
    try {
      final file = await cameraController.takePicture();
      return File(file.path);
    } catch (e) {
      debugPrint('Error capturing image: \$e');
      return null;
    }
  }

  bool hasNaturalVariation(List<double> list) {
    if (list.length < 5) return false;
    double variationCount = 0;
    for (int i = 1; i < list.length; i++) {
      if ((list[i] - list[i - 1]).abs() > 0.02) {
        variationCount++;
      }
    }
    return variationCount >= 3;
  }

  bool isFaceInsideCircle(Face face, Size screenSize) {
    final cameraPreviewSize = Size(
      cameraController.value.previewSize!.height,
      cameraController.value.previewSize!.width,
    );
    final scaleX = screenSize.width / cameraPreviewSize.width;
    final scaleY = screenSize.height / cameraPreviewSize.height;
    final adjustedFaceCenter = Offset(
      (face.boundingBox.left + face.boundingBox.width / 2) * scaleX,
      (face.boundingBox.top + face.boundingBox.height / 2) * scaleY,
    );
    final circleCenter = Offset(screenSize.width / 2, screenSize.height / 2);
    final circleRadius = screenSize.width * 0.4;
    final distance = (adjustedFaceCenter - circleCenter).distance;
    return distance < circleRadius * 0.8;
  }

  @override
  void dispose() {
    cameraController.stopImageStream();
    faceDetector.close();
    cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.amberAccent,
        centerTitle: true,
        title: const Text("Identity Verification"),
      ),
      body:
          isCameraInitialized
              ? Stack(
                children: [
                  Positioned.fill(child: CameraPreview(cameraController)),
                  CustomPaint(
                    painter: HeadMaskPainter(
                      borderColor:
                          verificationComplete
                              ? (verificationPassed ? Colors.green : Colors.red)
                              : (isFaceCentered ? Colors.white : Colors.red),
                    ),
                    child: Container(),
                  ),
                  if (isVerifying && !verificationComplete)
                    Positioned.fill(
                      child: Center(
                        child: SizedBox(
                          width: MediaQuery.of(context).size.width * 0.88,
                          height: MediaQuery.of(context).size.width * 0.88,
                          child: const CircularProgressIndicator(
                            strokeWidth: 1,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  if (isVerifying || verificationComplete)
                    Positioned(
                      top: MediaQuery.of(context).size.height * 0.28,
                      left: 32,
                      right: 32,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.75),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            verificationComplete
                                ? (verificationPassed
                                    ? '✔ Verification successful'
                                    : '❌ Verification failed')
                                : 'Verifying that you are a real human...',
                            style: TextStyle(
                              fontSize: 18,
                              color:
                                  verificationComplete
                                      ? (verificationPassed
                                          ? Colors.green
                                          : Colors.red)
                                      : Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  if (!isFaceCentered && !verificationComplete)
                    Positioned(
                      top: 100,
                      left: 20,
                      right: 20,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Please center your face inside the circle',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  // 📊 Probabilities Display
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Smile: ${(smilingProbability ?? 0).toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.white),
                          ),
                          Text(
                            'Left Eye: ${(leftEyeOpenProbability ?? 0).toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.white),
                          ),
                          Text(
                            'Right Eye: ${(rightEyeOpenProbability ?? 0).toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.white),
                          ),
                          Text(
                            'Head Y: ${(headEulerAngleY ?? 0).toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (challengeMode && selectedChallenge != null)
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        color: Colors.black54,
                        child: Text(
                          getChallengeText(selectedChallenge!),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              )
              : const Center(child: CircularProgressIndicator()),
    );
  }

  String getChallengeText(LivenessChallenge challenge) {
    switch (challenge) {
      case LivenessChallenge.smile:
        return 'Please smile 😊';
      case LivenessChallenge.blink:
        return 'Please blink 👁️';
      case LivenessChallenge.rightEyeWink:
        return 'Wink with your right eye 😉';
      case LivenessChallenge.leftEyeWink:
        return 'Wink with your left eye 😉';
      case LivenessChallenge.turnHeadLeft:
        return 'Turn your head left ↩️';
      case LivenessChallenge.turnHeadRight:
        return 'Turn your head right ↪️';
    }
  }
}

class HeadMaskPainter extends CustomPainter {
  final Color borderColor;

  HeadMaskPainter({required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint =
        Paint()
          ..color = Colors.black.withOpacity(0.5)
          ..style = PaintingStyle.fill;

    final circlePaint =
        Paint()
          ..color = borderColor
          ..strokeWidth = 4
          ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.4;

    final path =
        Path()
          ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
          ..addOval(Rect.fromCircle(center: center, radius: radius))
          ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, overlayPaint);
    canvas.drawCircle(center, radius, circlePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
// // باقي الـ imports كما هي
// import 'dart:io';
// import 'dart:math';
// import 'dart:typed_data';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// import 'package:camera/camera.dart';

// enum LivenessChallenge {
//   smile,
//   blink,
//   rightEyeWink,
//   leftEyeWink,
//   turnHeadLeft,
//   turnHeadRight,
// }

// class PassiveLivenessPage extends StatefulWidget {
//   const PassiveLivenessPage({super.key});

//   @override
//   _PassiveLivenessPageState createState() => _PassiveLivenessPageState();
// }

// class _PassiveLivenessPageState extends State<PassiveLivenessPage> {
//   final FaceDetector faceDetector = FaceDetector(
//     options: FaceDetectorOptions(
//       enableContours: true,
//       enableClassification: true,
//       minFaceSize: 0.3,
//       performanceMode: FaceDetectorMode.fast,
//     ),
//   );

//   late CameraController cameraController;
//   bool isCameraInitialized = false;
//   bool isDetecting = false;

//   double? smilingProbability;
//   double? leftEyeOpenProbability;
//   double? rightEyeOpenProbability;
//   double? headEulerAngleY;

//   bool isVerifying = false;
//   bool verificationComplete = false;
//   bool verificationPassed = false;
//   DateTime? verificationStartTime;

//   bool isFaceCentered = false;
//   int failedAttempts = 0;

//   bool challengeMode = false;
//   LivenessChallenge? selectedChallenge;
//   bool challengePassed = false;

//   double? _initialSmiling;
//   double? _lastLeftEyeOpen;
//   double? _lastRightEyeOpen;
//   double? _lastHeadY;
//   bool? hasBlink;
//   bool? hasHeadMove;
//   int _eyeClosedFrames = 0;
//   int _headMoveFrames = 0;

//   @override
//   void initState() {
//     super.initState();
//     initializeCamera();
//   }

//   Future<void> initializeCamera() async {
//     final cameras = await availableCameras();
//     final frontCamera = cameras.firstWhere(
//       (camera) => camera.lensDirection == CameraLensDirection.front,
//     );
//     cameraController = CameraController(
//       frontCamera,
//       ResolutionPreset.high,
//       enableAudio: false,
//     );
//     await cameraController.initialize();
//     if (mounted) {
//       setState(() => isCameraInitialized = true);
//       startFaceDetection();
//     }
//   }

//   void startFaceDetection() {
//     if (isCameraInitialized) {
//       cameraController.startImageStream((CameraImage image) {
//         if (!isDetecting) {
//           isDetecting = true;
//           detectFaces(image).then((_) => isDetecting = false);
//         }
//       });
//     }
//   }

//   Future<void> detectFaces(CameraImage image) async {
//     try {
//       final WriteBuffer allBytes = WriteBuffer();
//       for (Plane plane in image.planes) {
//         allBytes.putUint8List(plane.bytes);
//       }
//       final bytes = allBytes.done().buffer.asUint8List();

//       final inputImage = InputImage.fromBytes(
//         bytes: bytes,
//         metadata: InputImageMetadata(
//           size: Size(image.width.toDouble(), image.height.toDouble()),
//           rotation: InputImageRotation.rotation270deg,
//           format: InputImageFormat.nv21,
//           bytesPerRow: image.planes[0].bytesPerRow,
//         ),
//       );

//       final faces = await faceDetector.processImage(inputImage);
//       if (!mounted) return;

//       if (faces.isNotEmpty) {
//         final face = faces.first;
//         final screenSize = MediaQuery.of(context).size;
//         final centered = isFaceInsideCircle(face, screenSize);

//         setState(() {
//           smilingProbability = face.smilingProbability;
//           leftEyeOpenProbability = face.leftEyeOpenProbability;
//           rightEyeOpenProbability = face.rightEyeOpenProbability;
//           headEulerAngleY = face.headEulerAngleY;
//           isFaceCentered = centered;
//         });

//         if (!isFaceCentered) return;

//         // ✅ Passive Liveness Only (No Smile)
//         if (!isVerifying && !verificationComplete) {
//           isVerifying = true;
//           verificationStartTime = DateTime.now();
//           hasBlink = false;
//           hasHeadMove = false;
//           _eyeClosedFrames = 0;
//           _headMoveFrames = 0;
//           _lastLeftEyeOpen = face.leftEyeOpenProbability;
//           _lastRightEyeOpen = face.rightEyeOpenProbability;
//           _lastHeadY = face.headEulerAngleY;
//         }

//         if (isVerifying && !verificationComplete) {
//           final leftOpen = face.leftEyeOpenProbability ?? 1.0;
//           final rightOpen = face.rightEyeOpenProbability ?? 1.0;
//           final avgEyeOpen = (leftOpen + rightOpen) / 2;

//           // 👁 رمشة
//           if (avgEyeOpen < 0.3) {
//             _eyeClosedFrames++;
//           } else {
//             if (_eyeClosedFrames >= 1 &&
//                 (_lastLeftEyeOpen! - leftOpen).abs() > 0.2 &&
//                 (_lastRightEyeOpen! - rightOpen).abs() > 0.2) {
//               hasBlink = true;
//             }
//             _eyeClosedFrames = 0;
//           }

//           // ↔ حركة رأس
//           if (_lastHeadY != null && face.headEulerAngleY != null) {
//             final diff = (face.headEulerAngleY! - _lastHeadY!).abs();
//             if (diff > 5) _headMoveFrames++;
//           }

//           _lastLeftEyeOpen = face.leftEyeOpenProbability;
//           _lastRightEyeOpen = face.rightEyeOpenProbability;
//           _lastHeadY = face.headEulerAngleY;

//           final elapsed =
//               DateTime.now().difference(verificationStartTime!).inSeconds;
//           if (elapsed >= 5) {
//             isVerifying = false;
//             verificationComplete = true;

//             final passedConditions =
//                 [hasBlink == true, _headMoveFrames > 1].where((v) => v).length;

//             verificationPassed = passedConditions >= 1;

//             setState(() {});
//             await Future.delayed(const Duration(seconds: 1));

//             if (verificationPassed) {
//               final file = await captureAndReturnImage();
//               if (mounted) Navigator.pop(context, file);
//             } else {
//               failedAttempts++;
//               if (failedAttempts >= 3) {
//                 challengeMode = true;
//                 selectedChallenge = getRandomChallenge(
//                   allowed: [
//                     LivenessChallenge.blink,
//                     LivenessChallenge.turnHeadLeft,
//                     LivenessChallenge.turnHeadRight,
//                   ],
//                 );
//                 challengePassed = false;
//                 verificationStartTime = DateTime.now();
//                 setState(() {});
//               } else {
//                 await Future.delayed(const Duration(seconds: 1));
//                 setState(() {
//                   verificationComplete = false;
//                   isVerifying = false;
//                 });
//               }
//             }
//           }
//         }
//       } else {
//         setState(() => isFaceCentered = false);
//       }
//     } catch (e) {
//       debugPrint('Error in face detection: $e');
//     }
//   }

//   Future<File?> captureAndReturnImage() async {
//     try {
//       final file = await cameraController.takePicture();
//       return File(file.path);
//     } catch (e) {
//       debugPrint('Error capturing image: $e');
//       return null;
//     }
//   }

//   LivenessChallenge getRandomChallenge({List<LivenessChallenge>? allowed}) {
//     final random = Random();
//     final list = allowed ?? LivenessChallenge.values;
//     return list[random.nextInt(list.length)];
//   }

//   bool isFaceInsideCircle(Face face, Size screenSize) {
//     final cameraPreviewSize = Size(
//       cameraController.value.previewSize!.height,
//       cameraController.value.previewSize!.width,
//     );
//     final scaleX = screenSize.width / cameraPreviewSize.width;
//     final scaleY = screenSize.height / cameraPreviewSize.height;
//     final adjustedFaceCenter = Offset(
//       (face.boundingBox.left + face.boundingBox.width / 2) * scaleX,
//       (face.boundingBox.top + face.boundingBox.height / 2) * scaleY,
//     );
//     final circleCenter = Offset(screenSize.width / 2, screenSize.height / 2);
//     final circleRadius = screenSize.width * 0.4;
//     final distance = (adjustedFaceCenter - circleCenter).distance;
//     return distance < circleRadius * 0.8;
//   }

//   @override
//   void dispose() {
//     cameraController.stopImageStream();
//     faceDetector.close();
//     cameraController.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         backgroundColor: Colors.amberAccent,
//         centerTitle: true,
//         title: const Text("Identity Verification"),
//       ),
//       body:
//           isCameraInitialized
//               ? Stack(
//                 children: [
//                   Positioned.fill(child: CameraPreview(cameraController)),
//                   CustomPaint(
//                     painter: HeadMaskPainter(
//                       borderColor:
//                           verificationComplete
//                               ? (verificationPassed ? Colors.green : Colors.red)
//                               : (isFaceCentered ? Colors.white : Colors.red),
//                     ),
//                     child: Container(),
//                   ),
//                   if (isVerifying && !verificationComplete)
//                     Positioned.fill(
//                       child: Center(
//                         child: SizedBox(
//                           width: MediaQuery.of(context).size.width * 0.88,
//                           height: MediaQuery.of(context).size.width * 0.88,
//                           child: const CircularProgressIndicator(
//                             strokeWidth: 1,
//                             color: Colors.white,
//                           ),
//                         ),
//                       ),
//                     ),
//                   if (isVerifying || verificationComplete)
//                     Positioned(
//                       top: MediaQuery.of(context).size.height * 0.28,
//                       left: 32,
//                       right: 32,
//                       child: Center(
//                         child: Container(
//                           padding: const EdgeInsets.all(12),
//                           decoration: BoxDecoration(
//                             color: Colors.black.withOpacity(0.75),
//                             borderRadius: BorderRadius.circular(12),
//                           ),
//                           child: Text(
//                             verificationComplete
//                                 ? (verificationPassed
//                                     ? '✔ Verification successful'
//                                     : '❌ Verification failed')
//                                 : 'Verifying that you are a real human...',
//                             style: TextStyle(
//                               fontSize: 18,
//                               color:
//                                   verificationComplete
//                                       ? (verificationPassed
//                                           ? Colors.green
//                                           : Colors.red)
//                                       : Colors.white,
//                               fontWeight: FontWeight.bold,
//                             ),
//                             textAlign: TextAlign.center,
//                           ),
//                         ),
//                       ),
//                     ),
//                   if (!isFaceCentered && !verificationComplete)
//                     Positioned(
//                       top: 100,
//                       left: 20,
//                       right: 20,
//                       child: Container(
//                         padding: const EdgeInsets.all(10),
//                         decoration: BoxDecoration(
//                           color: Colors.red.withOpacity(0.8),
//                           borderRadius: BorderRadius.circular(10),
//                         ),
//                         child: const Text(
//                           'Please center your face inside the circle',
//                           style: TextStyle(
//                             color: Colors.white,
//                             fontSize: 18,
//                             fontWeight: FontWeight.bold,
//                           ),
//                           textAlign: TextAlign.center,
//                         ),
//                       ),
//                     ),
//                   Positioned(
//                     bottom: 16,
//                     left: 16,
//                     child: Container(
//                       padding: const EdgeInsets.all(8),
//                       color: Colors.black54,
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Text(
//                             'Smile: ${smilingProbability != null ? (smilingProbability! * 100).toStringAsFixed(2) : 'N/A'}%',
//                             style: const TextStyle(color: Colors.white),
//                           ),
//                           Text(
//                             'Blink: ${leftEyeOpenProbability != null && rightEyeOpenProbability != null ? (((leftEyeOpenProbability! + rightEyeOpenProbability!) / 2) * 100).toStringAsFixed(2) : 'N/A'}%',
//                             style: const TextStyle(color: Colors.white),
//                           ),
//                           Text(
//                             'Head Y: ${headEulerAngleY != null ? headEulerAngleY!.toStringAsFixed(2) : 'N/A'}°',
//                             style: const TextStyle(color: Colors.white),
//                           ),
//                         ],
//                       ),
//                     ),
//                   ),
//                 ],
//               )
//               : const Center(child: CircularProgressIndicator()),
//     );
//   }
// }

// class HeadMaskPainter extends CustomPainter {
//   final Color borderColor;

//   HeadMaskPainter({required this.borderColor});

//   @override
//   void paint(Canvas canvas, Size size) {
//     final overlayPaint =
//         Paint()
//           ..color = Colors.black.withOpacity(0.5)
//           ..style = PaintingStyle.fill;

//     final circlePaint =
//         Paint()
//           ..color = borderColor
//           ..strokeWidth = 4
//           ..style = PaintingStyle.stroke;

//     final center = Offset(size.width / 2, size.height / 2);
//     final radius = size.width * 0.4;

//     final path =
//         Path()
//           ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
//           ..addOval(Rect.fromCircle(center: center, radius: radius))
//           ..fillType = PathFillType.evenOdd;

//     canvas.drawPath(path, overlayPaint);
//     canvas.drawCircle(center, radius, circlePaint);
//   }

//   @override
//   bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
// }

// // باقي الـ imports كما هي
// import 'dart:io';
// import 'dart:math';
// import 'dart:typed_data';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// import 'package:camera/camera.dart';

// enum LivenessChallenge {
//   smile,
//   blink,
//   rightEyeWink,
//   leftEyeWink,
//   turnHeadLeft,
//   turnHeadRight,
// }

// class PassiveLivenessPage extends StatefulWidget {
//   const PassiveLivenessPage({super.key});

//   @override
//   _PassiveLivenessPageState createState() => _PassiveLivenessPageState();
// }

// class _PassiveLivenessPageState extends State<PassiveLivenessPage> {
//   final FaceDetector faceDetector = FaceDetector(
//     options: FaceDetectorOptions(
//       enableContours: true,
//       enableClassification: true,
//       minFaceSize: 0.3,
//       performanceMode: FaceDetectorMode.fast,
//     ),
//   );

//   late CameraController cameraController;
//   bool isCameraInitialized = false;
//   bool isDetecting = false;

//   double? smilingProbability;
//   double? leftEyeOpenProbability;
//   double? rightEyeOpenProbability;
//   double? headEulerAngleY;

//   bool isVerifying = false;
//   bool verificationComplete = false;
//   bool verificationPassed = false;
//   DateTime? verificationStartTime;

//   bool isFaceCentered = false;
//   int failedAttempts = 0;

//   bool challengeMode = false;
//   LivenessChallenge? selectedChallenge;
//   bool challengePassed = false;

//   double? _initialLeftEye;
//   double? _initialRightEye;
//   double? _initialHeadY;

//   List<double> smileList = [];
//   List<double> leftEyeList = [];
//   List<double> rightEyeList = [];
//   List<double> headYList = [];

//   @override
//   void initState() {
//     super.initState();
//     initializeCamera();
//   }

//   Future<void> initializeCamera() async {
//     final cameras = await availableCameras();
//     final frontCamera = cameras.firstWhere(
//       (camera) => camera.lensDirection == CameraLensDirection.front,
//     );
//     cameraController = CameraController(
//       frontCamera,
//       ResolutionPreset.high,
//       enableAudio: false,
//     );
//     await cameraController.initialize();
//     if (mounted) {
//       setState(() => isCameraInitialized = true);
//       startFaceDetection();
//     }
//   }

//   void startFaceDetection() {
//     if (isCameraInitialized) {
//       cameraController.startImageStream((CameraImage image) {
//         if (!isDetecting) {
//           isDetecting = true;
//           detectFaces(image).then((_) => isDetecting = false);
//         }
//       });
//     }
//   }

//   Future<void> detectFaces(CameraImage image) async {
//     try {
//       final WriteBuffer allBytes = WriteBuffer();
//       for (Plane plane in image.planes) {
//         allBytes.putUint8List(plane.bytes);
//       }
//       final bytes = allBytes.done().buffer.asUint8List();

//       final inputImage = InputImage.fromBytes(
//         bytes: bytes,
//         metadata: InputImageMetadata(
//           size: Size(image.width.toDouble(), image.height.toDouble()),
//           rotation: InputImageRotation.rotation270deg,
//           format: InputImageFormat.nv21,
//           bytesPerRow: image.planes[0].bytesPerRow,
//         ),
//       );

//       final faces = await faceDetector.processImage(inputImage);
//       if (!mounted) return;

//       if (faces.isNotEmpty) {
//         final face = faces.first;
//         final screenSize = MediaQuery.of(context).size;
//         final centered = isFaceInsideCircle(face, screenSize);

//         setState(() {
//           smilingProbability = face.smilingProbability;
//           leftEyeOpenProbability = face.leftEyeOpenProbability;
//           rightEyeOpenProbability = face.rightEyeOpenProbability;
//           headEulerAngleY = face.headEulerAngleY;
//           isFaceCentered = centered;
//         });

//         if (!isFaceCentered) return;

//         // ✅ Challenge Mode
//         if (challengeMode && selectedChallenge != null && !challengePassed) {
//           if (_initialLeftEye == null &&
//               _initialRightEye == null &&
//               _initialHeadY == null) {
//             _initialLeftEye = face.leftEyeOpenProbability ?? 0;
//             _initialRightEye = face.rightEyeOpenProbability ?? 0;
//             _initialHeadY = face.headEulerAngleY ?? 0;
//             verificationStartTime = DateTime.now();
//           }

//           final elapsed =
//               DateTime.now().difference(verificationStartTime!).inSeconds;
//           if (elapsed >= 5) {
//             Navigator.pop(context, null); // فشل التحدي
//             return;
//           }

//           switch (selectedChallenge!) {
//             case LivenessChallenge.blink:
//               final left = face.leftEyeOpenProbability ?? 0;
//               final right = face.rightEyeOpenProbability ?? 0;
//               if ((left < 0.3 || right < 0.3) &&
//                   (_initialLeftEye! > 0.6 && _initialRightEye! > 0.6)) {
//                 challengePassed = true;
//               }
//               break;
//             case LivenessChallenge.turnHeadLeft:
//               if ((_initialHeadY ?? 0) - (face.headEulerAngleY ?? 0) > 10) {
//                 challengePassed = true;
//               }
//               break;
//             case LivenessChallenge.turnHeadRight:
//               if ((face.headEulerAngleY ?? 0) - (_initialHeadY ?? 0) > 10) {
//                 challengePassed = true;
//               }
//               break;
//             default:
//               break;
//           }

//           if (challengePassed) {
//             final file = await captureAndReturnImage();
//             if (mounted) Navigator.pop(context, file);
//           }

//           return;
//         }

//         // ✅ Passive Liveness (with temporal variation)
//         if (!isVerifying && !verificationComplete) {
//           isVerifying = true;
//           verificationStartTime = DateTime.now();
//           smileList.clear();
//           leftEyeList.clear();
//           rightEyeList.clear();
//           headYList.clear();
//         }

//         if (isVerifying && !verificationComplete) {
//           smileList.add(face.smilingProbability ?? 0);
//           leftEyeList.add(face.leftEyeOpenProbability ?? 0);
//           rightEyeList.add(face.rightEyeOpenProbability ?? 0);
//           headYList.add(face.headEulerAngleY ?? 0);

//           final elapsed =
//               DateTime.now().difference(verificationStartTime!).inSeconds;
//           if (elapsed >= 5) {
//             isVerifying = false;
//             verificationComplete = true;

//             final eyeMoved =
//                 hasVariation(leftEyeList) || hasVariation(rightEyeList);
//             final smileChanged = hasVariation(smileList);
//             final headMoved = hasVariation(headYList);

//             final passedConditions =
//                 [eyeMoved, smileChanged, headMoved].where((v) => v).length;
//             verificationPassed = passedConditions >= 1;

//             setState(() {});

//             await Future.delayed(const Duration(seconds: 1));

//             if (verificationPassed) {
//               final file = await captureAndReturnImage();
//               if (mounted) Navigator.pop(context, file);
//             } else {
//               failedAttempts++;
//               if (failedAttempts >= 3) {
//                 challengeMode = true;
//                 selectedChallenge = getRandomChallenge(
//                   allowed: [
//                     LivenessChallenge.blink,
//                     LivenessChallenge.turnHeadLeft,
//                     LivenessChallenge.turnHeadRight,
//                   ],
//                 );
//                 challengePassed = false;
//                 _initialLeftEye = null;
//                 _initialRightEye = null;
//                 _initialHeadY = null;
//                 verificationStartTime = DateTime.now();
//                 setState(() {});
//               } else {
//                 await Future.delayed(const Duration(seconds: 1));
//                 setState(() {
//                   verificationComplete = false;
//                   isVerifying = false;
//                 });
//               }
//             }
//           }
//         }
//       } else {
//         setState(() => isFaceCentered = false);
//       }
//     } catch (e) {
//       debugPrint('Error in face detection: $e');
//     }
//   }

//   Future<File?> captureAndReturnImage() async {
//     try {
//       final file = await cameraController.takePicture();
//       return File(file.path);
//     } catch (e) {
//       debugPrint('Error capturing image: $e');
//       return null;
//     }
//   }

//   bool hasVariation(List<double> list) {
//     if (list.length < 5) return false;
//     final max = list.reduce(maxFunc);
//     final min = list.reduce(minFunc);
//     return (max - min).abs() > 0.15;
//   }

//   double maxFunc(double a, double b) => a > b ? a : b;
//   double minFunc(double a, double b) => a < b ? a : b;

//   LivenessChallenge getRandomChallenge({List<LivenessChallenge>? allowed}) {
//     final random = Random();
//     final list = allowed ?? LivenessChallenge.values;
//     return list[random.nextInt(list.length)];
//   }

//   bool isFaceInsideCircle(Face face, Size screenSize) {
//     final cameraPreviewSize = Size(
//       cameraController.value.previewSize!.height,
//       cameraController.value.previewSize!.width,
//     );
//     final scaleX = screenSize.width / cameraPreviewSize.width;
//     final scaleY = screenSize.height / cameraPreviewSize.height;
//     final adjustedFaceCenter = Offset(
//       (face.boundingBox.left + face.boundingBox.width / 2) * scaleX,
//       (face.boundingBox.top + face.boundingBox.height / 2) * scaleY,
//     );
//     final circleCenter = Offset(screenSize.width / 2, screenSize.height / 2);
//     final circleRadius = screenSize.width * 0.4;
//     final distance = (adjustedFaceCenter - circleCenter).distance;
//     return distance < circleRadius * 0.8;
//   }

//   @override
//   void dispose() {
//     cameraController.stopImageStream();
//     faceDetector.close();
//     cameraController.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         backgroundColor: Colors.amberAccent,
//         centerTitle: true,
//         title: const Text("Identity Verification"),
//       ),
//       body:
//           isCameraInitialized
//               ? Stack(
//                 children: [
//                   Positioned.fill(child: CameraPreview(cameraController)),
//                   CustomPaint(
//                     painter: HeadMaskPainter(
//                       borderColor:
//                           verificationComplete
//                               ? (verificationPassed ? Colors.green : Colors.red)
//                               : (isFaceCentered ? Colors.white : Colors.red),
//                     ),
//                     child: Container(),
//                   ),
//                   if (isVerifying && !verificationComplete)
//                     Positioned.fill(
//                       child: Center(
//                         child: SizedBox(
//                           width: MediaQuery.of(context).size.width * 0.88,
//                           height: MediaQuery.of(context).size.width * 0.88,
//                           child: const CircularProgressIndicator(
//                             strokeWidth: 1,
//                             color: Colors.white,
//                           ),
//                         ),
//                       ),
//                     ),
//                   if (isVerifying || verificationComplete)
//                     Positioned(
//                       top: MediaQuery.of(context).size.height * 0.28,
//                       left: 32,
//                       right: 32,
//                       child: Center(
//                         child: Container(
//                           padding: const EdgeInsets.all(12),
//                           decoration: BoxDecoration(
//                             color: Colors.black.withOpacity(0.75),
//                             borderRadius: BorderRadius.circular(12),
//                           ),
//                           child: Text(
//                             verificationComplete
//                                 ? (verificationPassed
//                                     ? '✔ Verification successful'
//                                     : '❌ Verification failed')
//                                 : 'Verifying that you are a real human...',
//                             style: TextStyle(
//                               fontSize: 18,
//                               color:
//                                   verificationComplete
//                                       ? (verificationPassed
//                                           ? Colors.green
//                                           : Colors.red)
//                                       : Colors.white,
//                               fontWeight: FontWeight.bold,
//                             ),
//                             textAlign: TextAlign.center,
//                           ),
//                         ),
//                       ),
//                     ),
//                   if (!isFaceCentered && !verificationComplete)
//                     Positioned(
//                       top: 100,
//                       left: 20,
//                       right: 20,
//                       child: Container(
//                         padding: const EdgeInsets.all(10),
//                         decoration: BoxDecoration(
//                           color: Colors.red.withOpacity(0.8),
//                           borderRadius: BorderRadius.circular(10),
//                         ),
//                         child: const Text(
//                           'Please center your face inside the circle',
//                           style: TextStyle(
//                             color: Colors.white,
//                             fontSize: 18,
//                             fontWeight: FontWeight.bold,
//                           ),
//                           textAlign: TextAlign.center,
//                         ),
//                       ),
//                     ),
//                   Positioned(
//                     bottom: 16,
//                     left: 16,
//                     child: Container(
//                       padding: const EdgeInsets.all(8),
//                       color: Colors.black54,
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Text(
//                             'Smile: ${smilingProbability != null ? (smilingProbability! * 100).toStringAsFixed(2) : 'N/A'}%',
//                             style: const TextStyle(color: Colors.white),
//                           ),
//                           Text(
//                             'Blink: ${leftEyeOpenProbability != null && rightEyeOpenProbability != null ? (((leftEyeOpenProbability! + rightEyeOpenProbability!) / 2) * 100).toStringAsFixed(2) : 'N/A'}%',
//                             style: const TextStyle(color: Colors.white),
//                           ),
//                           Text(
//                             'Head Y: ${headEulerAngleY != null ? headEulerAngleY!.toStringAsFixed(2) : 'N/A'}°',
//                             style: const TextStyle(color: Colors.white),
//                           ),
//                         ],
//                       ),
//                     ),
//                   ),
//                   if (challengeMode && selectedChallenge != null)
//                     Positioned(
//                       top: 16,
//                       left: 16,
//                       right: 16,
//                       child: Container(
//                         padding: const EdgeInsets.all(8),
//                         color: Colors.black54,
//                         child: Text(
//                           getChallengeText(selectedChallenge!),
//                           style: const TextStyle(
//                             color: Colors.white,
//                             fontSize: 18,
//                           ),
//                           textAlign: TextAlign.center,
//                         ),
//                       ),
//                     ),
//                 ],
//               )
//               : const Center(child: CircularProgressIndicator()),
//     );
//   }

//   String getChallengeText(LivenessChallenge challenge) {
//     switch (challenge) {
//       case LivenessChallenge.smile:
//         return 'Please smile 😊';
//       case LivenessChallenge.blink:
//         return 'Please blink 👁️';
//       case LivenessChallenge.rightEyeWink:
//         return 'Wink with your right eye 😉';
//       case LivenessChallenge.leftEyeWink:
//         return 'Wink with your left eye 😉';
//       case LivenessChallenge.turnHeadLeft:
//         return 'Turn your head left ↩️';
//       case LivenessChallenge.turnHeadRight:
//         return 'Turn your head right ↪️';
//     }
//   }
// }

// class HeadMaskPainter extends CustomPainter {
//   final Color borderColor;

//   HeadMaskPainter({required this.borderColor});

//   @override
//   void paint(Canvas canvas, Size size) {
//     final overlayPaint =
//         Paint()
//           ..color = Colors.black.withOpacity(0.5)
//           ..style = PaintingStyle.fill;

//     final circlePaint =
//         Paint()
//           ..color = borderColor
//           ..strokeWidth = 4
//           ..style = PaintingStyle.stroke;

//     final center = Offset(size.width / 2, size.height / 2);
//     final radius = size.width * 0.4;

//     final path =
//         Path()
//           ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
//           ..addOval(Rect.fromCircle(center: center, radius: radius))
//           ..fillType = PathFillType.evenOdd;

//     canvas.drawPath(path, overlayPaint);
//     canvas.drawCircle(center, radius, circlePaint);
//   }

//   @override
//   bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
// }


// // باقي الـ imports كما هي
// import 'dart:io';
// import 'dart:math';
// import 'dart:typed_data';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// import 'package:camera/camera.dart';

// enum LivenessChallenge {
//   smile,
//   blink,
//   rightEyeWink,
//   leftEyeWink,
//   turnHeadLeft,
//   turnHeadRight,
// }

// class PassiveLivenessPage extends StatefulWidget {
//   const PassiveLivenessPage({super.key});

//   @override
//   _PassiveLivenessPageState createState() => _PassiveLivenessPageState();
// }

// class _PassiveLivenessPageState extends State<PassiveLivenessPage> {
//   final FaceDetector faceDetector = FaceDetector(
//     options: FaceDetectorOptions(
//       enableContours: true,
//       enableClassification: true,
//       minFaceSize: 0.3,
//       performanceMode: FaceDetectorMode.fast,
//     ),
//   );

//   late CameraController cameraController;
//   bool isCameraInitialized = false;
//   bool isDetecting = false;

//   double? smilingProbability;
//   double? leftEyeOpenProbability;
//   double? rightEyeOpenProbability;
//   double? headEulerAngleY;

//   bool isVerifying = false;
//   bool verificationComplete = false;
//   bool verificationPassed = false;
//   DateTime? verificationStartTime;

//   bool isFaceCentered = false;
//   int failedAttempts = 0;

//   bool challengeMode = false;
//   LivenessChallenge? selectedChallenge;
//   bool challengePassed = false;

//   int smileFrames = 0;
//   int blinkFrames = 0;
//   int winkFrames = 0;
//   int headTurnFrames = 0;

//   double? _initialSmiling;
//   double? _initialLeftEye;
//   double? _initialRightEye;
//   double? _initialHeadY;

//   int _eyeClosedFrames = 0;
//   int _headMoveFrames = 0;

//   double? _lastLeftEyeOpen;
//   double? _lastRightEyeOpen;
//   double? _lastHeadY;
//   bool? hasBlink;
//   bool? hasHeadMove;
//   bool hasSmile = false;
//   int _smileFrames = 0;
//   @override
//   void initState() {
//     super.initState();
//     initializeCamera();
//   }

//   Future<void> initializeCamera() async {
//     final cameras = await availableCameras();
//     final frontCamera = cameras.firstWhere(
//       (camera) => camera.lensDirection == CameraLensDirection.front,
//     );
//     cameraController = CameraController(
//       frontCamera,
//       ResolutionPreset.high,
//       enableAudio: false,
//     );
//     await cameraController.initialize();
//     if (mounted) {
//       setState(() => isCameraInitialized = true);
//       startFaceDetection();
//     }
//   }

//   void startFaceDetection() {
//     if (isCameraInitialized) {
//       cameraController.startImageStream((CameraImage image) {
//         if (!isDetecting) {
//           isDetecting = true;
//           detectFaces(image).then((_) => isDetecting = false);
//         }
//       });
//     }
//   }

//   Future<void> detectFaces(CameraImage image) async {
//     try {
//       final WriteBuffer allBytes = WriteBuffer();
//       for (Plane plane in image.planes) {
//         allBytes.putUint8List(plane.bytes);
//       }
//       final bytes = allBytes.done().buffer.asUint8List();

//       final inputImage = InputImage.fromBytes(
//         bytes: bytes,
//         metadata: InputImageMetadata(
//           size: Size(image.width.toDouble(), image.height.toDouble()),
//           rotation: InputImageRotation.rotation270deg,
//           format: InputImageFormat.nv21,
//           bytesPerRow: image.planes[0].bytesPerRow,
//         ),
//       );

//       final faces = await faceDetector.processImage(inputImage);
//       if (!mounted) return;

//       if (faces.isNotEmpty) {
//         final face = faces.first;
//         final screenSize = MediaQuery.of(context).size;
//         final centered = isFaceInsideCircle(face, screenSize);

//         setState(() {
//           smilingProbability = face.smilingProbability;
//           leftEyeOpenProbability = face.leftEyeOpenProbability;
//           rightEyeOpenProbability = face.rightEyeOpenProbability;
//           headEulerAngleY = face.headEulerAngleY;
//           isFaceCentered = centered;
//         });

//         if (!isFaceCentered) return;

//         // ✅ Challenge Mode
//         if (challengeMode && selectedChallenge != null && !challengePassed) {
//           if (_initialLeftEye == null &&
//               _initialRightEye == null &&
//               _initialHeadY == null) {
//             _initialLeftEye = face.leftEyeOpenProbability ?? 0;
//             _initialRightEye = face.rightEyeOpenProbability ?? 0;
//             _initialHeadY = face.headEulerAngleY ?? 0;
//             verificationStartTime = DateTime.now();
//           }

//           final elapsed =
//               DateTime.now().difference(verificationStartTime!).inSeconds;
//           if (elapsed >= 5) {
//             Navigator.pop(context, null); // فشل التحدي
//             return;
//           }

//           switch (selectedChallenge!) {
//             case LivenessChallenge.blink:
//               final left = face.leftEyeOpenProbability ?? 0;
//               final right = face.rightEyeOpenProbability ?? 0;
//               if ((left < 0.3 || right < 0.3) &&
//                   (_initialLeftEye! > 0.6 && _initialRightEye! > 0.6)) {
//                 challengePassed = true;
//               }
//               break;
//             case LivenessChallenge.turnHeadLeft:
//               if ((_initialHeadY ?? 0) - (face.headEulerAngleY ?? 0) > 10) {
//                 challengePassed = true;
//               }
//               break;
//             case LivenessChallenge.turnHeadRight:
//               if ((face.headEulerAngleY ?? 0) - (_initialHeadY ?? 0) > 10) {
//                 challengePassed = true;
//               }
//               break;
//             default:
//               break;
//           }

//           if (challengePassed) {
//             final file = await captureAndReturnImage();
//             if (mounted) Navigator.pop(context, file);
//           }

//           return;
//         }

//         // ✅ Passive Liveness
//         if (!isVerifying && !verificationComplete) {
//           isVerifying = true;
//           verificationStartTime = DateTime.now();
//           hasBlink = false;
//           hasSmile = false;
//           hasHeadMove = false;
//           _eyeClosedFrames = 0;
//           _headMoveFrames = 0;
//           _smileFrames = 0;
//           _lastLeftEyeOpen = face.leftEyeOpenProbability;
//           _lastRightEyeOpen = face.rightEyeOpenProbability;
//           _lastHeadY = face.headEulerAngleY;
//           _initialSmiling = null;
//         }

//         if (isVerifying && !verificationComplete) {
//           final leftOpen = face.leftEyeOpenProbability ?? 1.0;
//           final rightOpen = face.rightEyeOpenProbability ?? 1.0;
//           final avgEyeOpen = (leftOpen + rightOpen) / 2;

//           // 👁 رمشة
//           if (avgEyeOpen < 0.3) {
//             _eyeClosedFrames++;
//           } else {
//             if (_eyeClosedFrames >= 1 &&
//                 (_lastLeftEyeOpen! - leftOpen).abs() > 0.2 &&
//                 (_lastRightEyeOpen! - rightOpen).abs() > 0.2) {
//               hasBlink = true;
//             }
//             _eyeClosedFrames = 0;
//           }

//           // 😄 ابتسامة
//           if (face.smilingProbability != null &&
//               face.smilingProbability! > 0.4 &&
//               (_initialSmiling == null ||
//                   (face.smilingProbability! - _initialSmiling!).abs() > 0.2)) {
//             _smileFrames++;
//           }
//           if (_smileFrames >= 2) hasSmile = true;

//           // ↔ حركة رأس
//           if (_lastHeadY != null && face.headEulerAngleY != null) {
//             final diff = (face.headEulerAngleY! - _lastHeadY!).abs();
//             if (diff > 5) _headMoveFrames++;
//           }

//           _lastLeftEyeOpen = face.leftEyeOpenProbability;
//           _lastRightEyeOpen = face.rightEyeOpenProbability;
//           _lastHeadY = face.headEulerAngleY;
//           _initialSmiling ??= face.smilingProbability;

//           final elapsed =
//               DateTime.now().difference(verificationStartTime!).inSeconds;
//           if (elapsed >= 5) {
//             isVerifying = false;
//             verificationComplete = true;

//             final passedConditions =
//                 [
//                   hasBlink == true,
//                   hasSmile == true,
//                   _headMoveFrames > 1,
//                 ].where((v) => v).length;

//             verificationPassed = passedConditions >= 1;

//             setState(() {});

//             await Future.delayed(const Duration(seconds: 1));

//             if (verificationPassed) {
//               final file = await captureAndReturnImage();
//               if (mounted) Navigator.pop(context, file);
//             } else {
//               failedAttempts++;
//               if (failedAttempts >= 3) {
//                 challengeMode = true;
//                 selectedChallenge = getRandomChallenge(
//                   allowed: [
//                     LivenessChallenge.blink,
//                     LivenessChallenge.turnHeadLeft,
//                     LivenessChallenge.turnHeadRight,
//                   ],
//                 );
//                 challengePassed = false;
//                 _initialSmiling = null;
//                 _initialLeftEye = null;
//                 _initialRightEye = null;
//                 _initialHeadY = null;
//                 verificationStartTime = DateTime.now();
//                 setState(() {});
//               } else {
//                 await Future.delayed(const Duration(seconds: 1));
//                 setState(() {
//                   verificationComplete = false;
//                   isVerifying = false;
//                 });
//               }
//             }
//           }
//         }
//       } else {
//         setState(() => isFaceCentered = false);
//       }
//     } catch (e) {
//       debugPrint('Error in face detection: $e');
//     }
//   }


//   Future<File?> captureAndReturnImage() async {
//     try {
//       final file = await cameraController.takePicture();
//       return File(file.path);
//     } catch (e) {
//       debugPrint('Error capturing image: $e');
//       return null;
//     }
//   }

//   LivenessChallenge getRandomChallenge({List<LivenessChallenge>? allowed}) {
//     final random = Random();
//     final list = allowed ?? LivenessChallenge.values;
//     return list[random.nextInt(list.length)];
//   }

//   bool isFaceInsideCircle(Face face, Size screenSize) {
//     final cameraPreviewSize = Size(
//       cameraController.value.previewSize!.height,
//       cameraController.value.previewSize!.width,
//     );
//     final scaleX = screenSize.width / cameraPreviewSize.width;
//     final scaleY = screenSize.height / cameraPreviewSize.height;
//     final adjustedFaceCenter = Offset(
//       (face.boundingBox.left + face.boundingBox.width / 2) * scaleX,
//       (face.boundingBox.top + face.boundingBox.height / 2) * scaleY,
//     );
//     final circleCenter = Offset(screenSize.width / 2, screenSize.height / 2);
//     final circleRadius = screenSize.width * 0.4;
//     final distance = (adjustedFaceCenter - circleCenter).distance;
//     return distance < circleRadius * 0.8;
//   }

//   @override
//   void dispose() {
//     cameraController.stopImageStream();
//     faceDetector.close();
//     cameraController.dispose();
//     super.dispose();
//   }

//   @override
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         backgroundColor: Colors.amberAccent,
//         centerTitle: true,
//         title: const Text("Identity Verification"),
//       ),
//       body:
//           isCameraInitialized
//               ? Stack(
//                 children: [
//                   // الكاميرا
//                   Positioned.fill(child: CameraPreview(cameraController)),

//                   // دائرة التمركز
//                   CustomPaint(
//                     painter: HeadMaskPainter(
//                       borderColor:
//                           verificationComplete
//                               ? (verificationPassed ? Colors.green : Colors.red)
//                               : (isFaceCentered ? Colors.white : Colors.red),
//                     ),
//                     child: Container(),
//                   ),

//                   // اللودينج حول الدائرة أثناء التحقق
//                   if (isVerifying && !verificationComplete)
//                     Positioned.fill(
//                       child: Center(
//                         child: SizedBox(
//                           width: MediaQuery.of(context).size.width * 0.88,
//                           height: MediaQuery.of(context).size.width * 0.88,
//                           child: const CircularProgressIndicator(
//                             strokeWidth: 1,
//                             color: Colors.white,
//                           ),
//                         ),
//                       ),
//                     ),

//                   // الرسالة داخل الدائرة (أثناء التحقق أو بعده)
//                   // الرسالة فوق الدائرة (أثناء التحقق أو بعده)
//                   if (isVerifying || verificationComplete)
//                     Positioned(
//                       top: MediaQuery.of(context).size.height * 0.28,
//                       left: 32,
//                       right: 32,
//                       child: Center(
//                         child: Container(
//                           padding: const EdgeInsets.all(12),
//                           decoration: BoxDecoration(
//                             color: Colors.black.withOpacity(0.75),
//                             borderRadius: BorderRadius.circular(12),
//                           ),
//                           child: Text(
//                             verificationComplete
//                                 ? (verificationPassed
//                                     ? '✔ Verification successful'
//                                     : '❌ Verification failed')
//                                 : 'Verifying that you are a real human...',
//                             style: TextStyle(
//                               fontSize: 18,
//                               color:
//                                   verificationComplete
//                                       ? (verificationPassed
//                                           ? Colors.green
//                                           : Colors.red)
//                                       : Colors.white,
//                               fontWeight: FontWeight.bold,
//                             ),
//                             textAlign: TextAlign.center,
//                           ),
//                         ),
//                       ),
//                     ),

//                   // رسالة تمركز الوجه (إذا لم يكن في المنتصف)
//                   if (!isFaceCentered && !verificationComplete)
//                     Positioned(
//                       top: 100,
//                       left: 20,
//                       right: 20,
//                       child: Container(
//                         padding: const EdgeInsets.all(10),
//                         decoration: BoxDecoration(
//                           color: Colors.red.withOpacity(0.8),
//                           borderRadius: BorderRadius.circular(10),
//                         ),
//                         child: const Text(
//                           'Please center your face inside the circle',
//                           style: TextStyle(
//                             color: Colors.white,
//                             fontSize: 18,
//                             fontWeight: FontWeight.bold,
//                           ),
//                           textAlign: TextAlign.center,
//                         ),
//                       ),
//                     ),

//                   // النسب الثلاثة (smile / blink / head)
//                   Positioned(
//                     bottom: 16,
//                     left: 16,
//                     child: Container(
//                       padding: const EdgeInsets.all(8),
//                       color: Colors.black54,
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Text(
//                             'Smile: ${smilingProbability != null ? (smilingProbability! * 100).toStringAsFixed(2) : 'N/A'}%',
//                             style: const TextStyle(color: Colors.white),
//                           ),
//                           Text(
//                             'Blink: ${leftEyeOpenProbability != null && rightEyeOpenProbability != null ? (((leftEyeOpenProbability! + rightEyeOpenProbability!) / 2) * 100).toStringAsFixed(2) : 'N/A'}%',
//                             style: const TextStyle(color: Colors.white),
//                           ),
//                           Text(
//                             'Head Y: ${headEulerAngleY != null ? headEulerAngleY!.toStringAsFixed(2) : 'N/A'}°',
//                             style: const TextStyle(color: Colors.white),
//                           ),
//                         ],
//                       ),
//                     ),
//                   ),

//                   // إذا المستخدم في وضع challenge
//                   if (challengeMode && selectedChallenge != null)
//                     Positioned(
//                       top: 16,
//                       left: 16,
//                       right: 16,
//                       child: Container(
//                         padding: const EdgeInsets.all(8),
//                         color: Colors.black54,
//                         child: Text(
//                           getChallengeText(selectedChallenge!),
//                           style: const TextStyle(
//                             color: Colors.white,
//                             fontSize: 18,
//                           ),
//                           textAlign: TextAlign.center,
//                         ),
//                       ),
//                     ),
//                 ],
//               )
//               : const Center(child: CircularProgressIndicator()),
//     );
//   }

//   String getChallengeText(LivenessChallenge challenge) {
//     switch (challenge) {
//       case LivenessChallenge.smile:
//         return 'Please smile 😊';
//       case LivenessChallenge.blink:
//         return 'Please blink 👁️';
//       case LivenessChallenge.rightEyeWink:
//         return 'Wink with your right eye 😉';
//       case LivenessChallenge.leftEyeWink:
//         return 'Wink with your left eye 😉';
//       case LivenessChallenge.turnHeadLeft:
//         return 'Turn your head left ↩️';
//       case LivenessChallenge.turnHeadRight:
//         return 'Turn your head right ↪️';
//     }
//   }
// }

// class HeadMaskPainter extends CustomPainter {
//   final Color borderColor;

//   HeadMaskPainter({required this.borderColor});

//   @override
//   void paint(Canvas canvas, Size size) {
//     final overlayPaint =
//         Paint()
//           ..color = Colors.black.withOpacity(0.5)
//           ..style = PaintingStyle.fill;

//     final circlePaint =
//         Paint()
//           ..color = borderColor
//           ..strokeWidth = 4
//           ..style = PaintingStyle.stroke;

//     final center = Offset(size.width / 2, size.height / 2);
//     final radius = size.width * 0.4;

//     final path =
//         Path()
//           ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
//           ..addOval(Rect.fromCircle(center: center, radius: radius))
//           ..fillType = PathFillType.evenOdd;

//     canvas.drawPath(path, overlayPaint);
//     canvas.drawCircle(center, radius, circlePaint);
//   }

//   @override
//   bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
// }
