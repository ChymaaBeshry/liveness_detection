import 'dart:async';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'dart:typed_data';

class PassiveLivenessPage extends StatefulWidget {
  const PassiveLivenessPage({super.key});

  @override
  State<PassiveLivenessPage> createState() => _PassiveLivenessPageState();
}

class _PassiveLivenessPageState extends State<PassiveLivenessPage> {
  late CameraController _controller;
  late FaceDetector _faceDetector;
  bool _isCameraInitialized = false;
  bool _isDetecting = false;
  bool _faceInsideCircle = false;

  bool blinked = false;
  bool smiled = false;
  bool headMoved = false;
  Offset? previousHeadPosition;

  Timer? _livenessTimer;
  bool _isVerifying = false;
  String message = "من فضلك ضع وجهك في المنتصف";
  Color borderColor = Colors.red;
  bool showCheckMark = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableLandmarks: true,
        performanceMode: FaceDetectorMode.fast,
      ),
    );
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
    );
    _controller = CameraController(
      frontCamera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    await _controller.initialize();
    setState(() => _isCameraInitialized = true);
    _controller.startImageStream(_processCameraImage);
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isDetecting || !_isCameraInitialized) return;
    _isDetecting = true;

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

      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isEmpty || !mounted) {
        _isDetecting = false;
        return;
      }

      final face = faces.first;
      _faceInsideCircle = _isFaceCentered(face);

      if (_faceInsideCircle) {
        if (!_isVerifying) {
          _startVerification(face);
        } else {
          _analyzeLiveness(face);
        }
      } else {
        _cancelVerification();
      }
    } catch (e) {
      debugPrint("❗ Error: $e");
    } finally {
      _isDetecting = false;
    }
  }

  bool _isFaceCentered(Face face) {
    final previewSize = _controller.value.previewSize;
    if (previewSize == null) return false;

    final screenSize = MediaQuery.of(context).size;
    final center = Offset(screenSize.width / 2, screenSize.height / 2);
    final radius = screenSize.width * 0.25;

    List<FaceLandmarkType> requiredLandmarks = [
      FaceLandmarkType.leftEye,
      FaceLandmarkType.rightEye,
      FaceLandmarkType.noseBase,
      FaceLandmarkType.bottomMouth,
    ];

    for (var type in requiredLandmarks) {
      final landmark = face.landmarks[type];
      if (landmark == null) return false;

      double relativeX = landmark.position.x / previewSize.height;
      double relativeY = landmark.position.y / previewSize.width;
      double screenX = relativeX * screenSize.width;
      double screenY = relativeY * screenSize.height;

      final distance = sqrt(
        pow(screenX - center.dx, 2) + pow(screenY - center.dy, 2),
      );
      if (distance > radius) return false;
    }
    return true;
  }

  void _startVerification(Face face) {
    print("✅ الوجه في المنتصف. بدء التحقق لمدة 5 ثوانٍ...");
    setState(() {
      message = "جاري التحقق من أنك إنسان...";
      borderColor = Colors.white;
      _isVerifying = true;
      blinked = false;
      smiled = false;
      headMoved = false;
      showCheckMark = false;
    });

    _livenessTimer = Timer(const Duration(seconds: 5), () {
      final isHuman = blinked || smiled || headMoved;

      print("🔍 نتائج التحقق:");
      print("👁️ Blink: $blinked");
      print("😊 Smile: $smiled");
      print("↔️ Head movement: $headMoved");

      setState(() {
        borderColor = isHuman ? Colors.green : Colors.red;
        message = isHuman ? "تم التحقق بنجاح ✅" : "فشل التحقق ❌";
        showCheckMark = isHuman;
        _isVerifying = false;
      });
    });

    _analyzeLiveness(face);
  }

  void _cancelVerification() {
    if (_isVerifying) {
      _livenessTimer?.cancel();
      setState(() {
        _isVerifying = false;
        message = "من فضلك ضع وجهك في المنتصف";
        borderColor = Colors.red;
        showCheckMark = false;
      });
      print("🚫 الوجه خرج من المنتصف، تم إلغاء التحقق.");
    }
  }

  void _analyzeLiveness(Face face) {
    final rightEyeOpen = face.rightEyeOpenProbability;
    final leftEyeOpen = face.leftEyeOpenProbability;
    if ((rightEyeOpen != null && rightEyeOpen < 0.4) ||
        (leftEyeOpen != null && leftEyeOpen < 0.4)) {
      blinked = true;
    }

    final smileProb = face.smilingProbability;
    if (smileProb != null && smileProb > 0.7) {
      smiled = true;
    }

    final headPos = Offset(
      face.boundingBox.center.dx,
      face.boundingBox.center.dy,
    );
    if (previousHeadPosition != null &&
        (headPos - previousHeadPosition!).distance > 15) {
      headMoved = true;
    }
    previousHeadPosition = headPos;

    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    _faceDetector.close();
    _livenessTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body:
          _isCameraInitialized
              ? Stack(
                children: [
                  Positioned.fill(child: CameraPreview(_controller)),
                  Center(
                    child: Container(
                      width: MediaQuery.of(context).size.width,
                      height: MediaQuery.of(context).size.width,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: borderColor, width: 4),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (_isVerifying)
                            const CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (showCheckMark)
                                const Icon(
                                  Icons.check_circle,
                                  size: 48,
                                  color: Colors.green,
                                ),
                              Text(
                                message,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
              : const Center(child: CircularProgressIndicator()),
    );
  }
}
