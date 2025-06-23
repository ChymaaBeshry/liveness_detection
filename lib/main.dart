import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liveness_detection/liveness_detection.dart';
// import 'package:liveness_detection/blink_page.dart';
// import 'package:liveness_detection/right_eye_wink.dart';
// import 'package:liveness_detection/smile_setection.dart';
// import 'package:liveness_detection/turn_head_left.dart';
// import 'package:liveness_detection/turn_head_right.dart';
import 'package:permission_handler/permission_handler.dart';
// //import 'face_detection_page.dart';
import 'package:camera/camera.dart';
// import 'package:liveness_detection/right_eye_wink.dart';
// import 'package:liveness_detection/left_eye_wink.dart';
// import 'dart:math'; // مهم

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await requestCameraPermission();

  runApp(const MyApp());
}

/// Requests camera permission from the user.
Future<void> requestCameraPermission() async {
  final status = await Permission.camera.request();
  if (!status.isGranted) {
    // Handle permission denial
    runApp(const PermissionDeniedApp());
  }
}

class PermissionDeniedApp extends StatelessWidget {
  const PermissionDeniedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text("Permission Denied")),
        body: Center(
          child: AlertDialog(
            title: const Text("Permission Denied"),
            content: const Text("Camera access is required for verification."),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text("OK"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(title: 'Material App', home: HomePage());
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    // challenges.addAll([
    //   const RightEyeWinkPage(),
    //   const LeftEyeWinkPage(),
    //   const SmileDetection(),
    //   const TurnHeadRightPage(),
    //   const TurnHeadLeftPage(),
    //   const BlinkPage(),
    // ]);
  }

  // final challenges = [];
  File? img;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.amberAccent,
        toolbarHeight: 70,
        centerTitle: true,
        title: const Text('Verify Your Identity'),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Please click the button below to start verification',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20),
              ),
              const SizedBox(height: 30),
              img == null ? const SizedBox() : Image.file(img!),
              const SizedBox(height: 30),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  foregroundColor: Colors.black,
                  backgroundColor: Colors.amberAccent,
                ),
                onPressed: () async {
                  final cameras = await availableCameras();
                  if (cameras.isNotEmpty) {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) {
                          return PassiveLivenessPage();
                          // final random = Random();
                          // return challenges[random.nextInt(challenges.length)];
                        },
                      ),
                    ).then((v) {
                      print("------v:${v.toString()}");
                      print(
                        "------v:${v != null && v is File && v.path.isNotEmpty}",
                      );

                      if (v != null && v is File && v.path.isNotEmpty) {
                        img = v;
                      } else {
                        img = null;
                      }
                      setState(() {});
                    });
                    if (result == true) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Verification Successful!'),
                        ),
                      );
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Camera not active!')),
                    );
                  }
                },
                child: const Text(
                  'Verify Now',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
