import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show SystemChrome, DeviceOrientation;
import 'package:liveness_detection/head_mask_painter.dart';
import 'package:liveness_detection/turn_head_right.dart';

class TurnHeadLeftPage extends StatefulWidget {
  const TurnHeadLeftPage({super.key});

  @override
  _TurnHeadLeftPageState createState() => _TurnHeadLeftPageState();
}

class _TurnHeadLeftPageState extends State<TurnHeadLeftPage> {
  late CameraController cameraController;
  final FaceDetector faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableLandmarks: true,
      enableContours: true,
      performanceMode: FaceDetectorMode.accurate,
      minFaceSize: 0.3,
    ),
  );

  bool isCameraInitialized = false;
  bool isDetecting = false;
  bool isFaceInsideCircle = false;
  bool wasInsideCircle = false;
  bool turnedLeft = false;
  bool showSuccess = false;
  bool timerStarted = false;

  Timer? turnTimer;
  String message = "رجاءً ضع وجهك داخل الدائرة";

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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
      startDetection();
    }
  }

  void startDetection() {
    cameraController.startImageStream((CameraImage image) async {
      if (isDetecting) return;
      isDetecting = true;
      await detectFaces(image);
      isDetecting = false;
    });
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
      if (faces.isEmpty || !mounted) return;

      final face = faces.first;
      final inside = areAllKeyPointsInsideCircle(face);

      setState(() {
        isFaceInsideCircle = inside;
      });

      if (!inside) {
        if (wasInsideCircle) {
          turnTimer?.cancel();
          timerStarted = false;
        }
        setState(() {
          message = "رجاءً ضع وجهك داخل الدائرة";
          wasInsideCircle = false;
        });
        return;
      }

      if (!wasInsideCircle) {
        setState(() {
          message = "لف رأسك جهة اليسار";
          wasInsideCircle = true;
        });
        if (!timerStarted) {
          timerStarted = true;
          turnTimer = Timer(const Duration(seconds: 5), () {
            if (!turnedLeft && mounted) {
              Navigator.pop(context, false);
            }
          });
        }
      }

      final headEulerY = face.headEulerAngleY;

      if (headEulerY != null && headEulerY < -15) {
        if (!turnedLeft) {
          setState(() {
            turnedLeft = true;
            showSuccess = true;
            message = "تم التحقق بنجاح ✅";
          });

          await Future.delayed(const Duration(seconds: 2));
          if (mounted) Navigator.pop(context, true);
        }
      }
    } catch (e) {
      debugPrint("❗ خطأ أثناء تحليل الوجه: $e");
    }
  }

  bool areAllKeyPointsInsideCircle(Face face) {
    final previewSize = cameraController.value.previewSize;
    if (previewSize == null) return false;

    final screenSize = MediaQuery.of(context).size;
    final centerX = screenSize.width / 2;
    final centerY = screenSize.height / 2;
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

      final dx = screenX - centerX;
      final dy = screenY - centerY;
      final distance = sqrt(dx * dx + dy * dy);

      if (distance > radius) return false;
    }
    return true;
  }

  @override
  void dispose() {
    cameraController.dispose();
    faceDetector.close();
    turnTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("تحقق من الهوية - لف الرأس لليسار"),
        backgroundColor: Colors.amberAccent,
        centerTitle: true,
      ),
      body:
          isCameraInitialized
              ? Stack(
                children: [
                  Positioned.fill(child: CameraPreview(cameraController)),
                  CustomPaint(painter: HeadMaskPainter(), child: Container()),
                  if (!showSuccess)
                    Positioned(
                      top: 100,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            message,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (showSuccess)
                    const Center(
                      child: Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 100,
                      ),
                    ),
                ],
              )
              : const Center(child: CircularProgressIndicator()),
    );
  }
}
