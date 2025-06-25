// باقي الـ imports كما هي
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:camera/camera.dart';
import 'package:liveness_detection/liveness_analyzer.dart';

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
  double? _initialHeadX;
  double? _initialHeadZ;
  double? _initialSmile;

  List<double> smileList = [];
  List<double> leftEyeList = [];
  List<double> rightEyeList = [];
  List<double> headYList = [];
  List<double> headxList = [];
  List<double> headzList = [];
  File? imgFile;
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

  double calcAvg(List<double> list) {
    double sum = 0;
    list.forEach((i) {
      sum += i;
    });
    return double.parse((sum / list.length).toString().substring(0, 4));
  }

  int detectChangeFrame(List<double> List, {double threshold = 0.2}) {
    for (int i = 1; i < List.length; i++) {
      if ((List[i] - List[i - 1]).abs() > threshold) {
        return i; // frame number where significant change happened
      }
    }
    return 0; // no change detected
  }
  //img
  //z smile=> 0.10   - f=> -1
  //s smile=> (0.33 - 0.20)   -  f=> 6
  //b smile=> (0.99 ) -  f=> -1

  //per
  //s smile=> (0.33 - 0.20)   -  f=> 6
  //z smill=> 0.010  -  f=> 2
  //b smile=> (0.2727 - 0.30) -  f=> 4

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

  Future<void> takePhoto() async {
    imgFile = await captureAndReturnImage();
    print("-----iam here img:${imgFile?.path}");
    await Future.delayed(const Duration(microseconds: 500));
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
              _initialHeadX == null &&
              _initialHeadZ == null &&
              _initialSmile == null) {
            _initialLeftEye = face.leftEyeOpenProbability ?? 0;
            _initialRightEye = face.rightEyeOpenProbability ?? 0;
            _initialHeadY = face.headEulerAngleY ?? 0;
            _initialHeadX = face.headEulerAngleX ?? 0;
            _initialHeadZ = face.headEulerAngleZ ?? 0;
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
            print("----- Challenge passed");
            await takePhoto();
            if (mounted) Navigator.pop(context, imgFile);
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
          headxList.clear();
          headzList.clear();
        }

        if (isVerifying && !verificationComplete) {
          smileList.add(
            double.tryParse(face.smilingProbability!.toStringAsFixed(3)) ?? 0,
          );
          leftEyeList.add(
            double.tryParse(face.leftEyeOpenProbability!.toStringAsFixed(3)) ??
                0,
          );
          rightEyeList.add(
            double.tryParse(face.rightEyeOpenProbability!.toStringAsFixed(3)) ??
                0,
          );
          headYList.add(
            double.tryParse(face.headEulerAngleY!.toStringAsFixed(3)) ?? 0,
          );
          headxList.add(
            double.tryParse(face.headEulerAngleX!.toStringAsFixed(3)) ?? 0,
          );
          headzList.add(
            double.tryParse(face.headEulerAngleZ!.toStringAsFixed(3)) ?? 0,
          );

          final elapsed =
              DateTime.now().difference(verificationStartTime!).inSeconds;
          if (elapsed >= 5) {
            isVerifying = false;
            verificationComplete = true;

            final analyzer = LivenessAnalyzer();
            final isReal = analyzer.analyze(
              smileList: smileList,
              leftEyeList: leftEyeList,
              rightEyeList: rightEyeList,
              headYList: headYList,
              headXList: headxList,
              headZList: headzList,
            );

            debugPrint('Analyzer Result: $isReal');
            debugPrint(
              'Analyzer STD → Smile: ${analyzer.calcStd(smileList).toStringAsFixed(3)}, '
              'LeftEye: ${analyzer.calcStd(leftEyeList).toStringAsFixed(3)}, '
              'RightEye: ${analyzer.calcStd(rightEyeList).toStringAsFixed(3)}, '
              'HeadY: ${analyzer.calcStd(headYList).toStringAsFixed(3)}, '
              'HeadX: ${analyzer.calcStd(headxList).toStringAsFixed(3)}, '
              'HeadZ: ${analyzer.calcStd(headzList).toStringAsFixed(3)}',
            );

            debugPrint(
              'Analyzer Changes → Smile: ${analyzer.countChangeFrames(smileList, threshold: analyzer.smileFrameChangeThreshold)}, '
              'LeftEye: ${analyzer.countChangeFrames(leftEyeList, threshold: analyzer.eyeFrameChangeThreshold)}, '
              'RightEye: ${analyzer.countChangeFrames(rightEyeList, threshold: analyzer.eyeFrameChangeThreshold)}, '
              'HeadY: ${analyzer.countChangeFrames(headYList, threshold: analyzer.headYFrameChangeThreshold)}, '
              'HeadX: ${analyzer.countChangeFrames(headxList, threshold: analyzer.headXFrameChangeThreshold)}, '
              'HeadZ: ${analyzer.countChangeFrames(headzList, threshold: analyzer.headZFrameChangeThreshold)}',
            );

            if (isReal) {
              await takePhoto();
              verificationPassed = true;
            }

            setState(() {});
            await Future.delayed(const Duration(seconds: 1));

            if (verificationPassed) {
              if (mounted) Navigator.pop(context, imgFile);
            } else {
              failedAttempts++;
              if (failedAttempts >= 3) {
                challengeMode = true;
                selectedChallenge = getRandomChallenge();
                challengePassed = false;
                _initialLeftEye = null;
                _initialRightEye = null;
                _initialHeadY = null;
                _initialHeadX = null;
                _initialHeadZ = null;
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
      debugPrint('Error in face detection: $e');
    }
  }

  List<double> smoothList(List<double> list, [int windowSize = 3]) {
    List<double> smoothed = [];
    for (int i = 0; i < list.length - windowSize + 1; i++) {
      double windowAvg = 0;
      for (int j = i; j < i + windowSize; j++) {
        windowAvg += list[j];
      }
      windowAvg /= windowSize;
      smoothed.add(windowAvg);
    }
    return smoothed;
  }

  bool hasHeadMoved(List<double> list, {double threshold = 5.0}) {
    if (list.length < 2) return false;
    double min = list.reduce((a, b) => a < b ? a : b);
    double max = list.reduce((a, b) => a > b ? a : b);
    double diff = (max - min).abs();
    debugPrint('Head movement diff: $diff');
    return diff > threshold;
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
                          verificationComplete || challengePassed
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
                            verificationComplete || challengePassed
                                ? (verificationPassed || challengePassed
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



// 1- calc proba
//2- get diffrences 
//3- kam frame 
