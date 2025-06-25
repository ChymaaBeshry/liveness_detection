import 'dart:math';

import 'package:flutter/material.dart';

class LivenessAnalyzer {
  final double smileStdThreshold;
  final double eyeStdThreshold;
  final double headYStdThreshold;
  final double headXStdThreshold;
  final double headZStdThreshold;

  final int smileFrameThreshold;
  final int eyeFrameThreshold;
  final int headYFrameThreshold;
  final int headXFrameThreshold;
  final int headZFrameThreshold;

  final double smileFrameChangeThreshold;
  final double eyeFrameChangeThreshold;
  final double headYFrameChangeThreshold;
  final double headXFrameChangeThreshold;
  final double headZFrameChangeThreshold;

  final double smileNeutralThreshold;
  final double eyeNeutralThreshold;
  final double headYNeutralThreshold;
  final double headXNeutralThreshold;
  final double headZNeutralThreshold;

  const LivenessAnalyzer({
    this.smileStdThreshold = 0.18,
    this.eyeStdThreshold = 0.07,
    this.headYStdThreshold = 0.3,
    this.headXStdThreshold = 0.3,
    this.headZStdThreshold = 0.3,

    this.smileFrameThreshold = 5,
    this.eyeFrameThreshold = 2,
    this.headYFrameThreshold = 3,
    this.headXFrameThreshold = 3,
    this.headZFrameThreshold = 3,

    this.smileFrameChangeThreshold = 0.05,
    this.eyeFrameChangeThreshold = 0.04,
    this.headYFrameChangeThreshold = 0.2,
    this.headXFrameChangeThreshold = 0.2,
    this.headZFrameChangeThreshold = 0.2,

    this.smileNeutralThreshold = 0.05,
    this.eyeNeutralThreshold = 0.05,
    this.headYNeutralThreshold = 0.3,
    this.headXNeutralThreshold = 0.3,
    this.headZNeutralThreshold = 0.3,
  });

  double calcStd(List<double> list) {
    if (list.isEmpty) return 0;
    final mean = list.reduce((a, b) => a + b) / list.length;
    final variance =
        list.map((x) => pow(x - mean, 2)).reduce((a, b) => a + b) / list.length;
    return sqrt(variance);
  }

  int countChangeFrames(List<double> list, {required double threshold}) {
    int count = 0;
    for (int i = 1; i < list.length; i++) {
      if ((list[i] - list[i - 1]).abs() > threshold) {
        count++;
      }
    }
    return count;
  }

  bool isLikelyNeutral({
    required double smileStd,
    required double eyeStd,
    required double headYStd,
    required double headXStd,
    required double headZStd,
  }) {
    return smileStd <= smileNeutralThreshold &&
        eyeStd <= eyeNeutralThreshold &&
        headYStd <= headYNeutralThreshold &&
        headXStd <= headXNeutralThreshold &&
        headZStd <= headZNeutralThreshold;
  }

  bool analyze({
    required List<double> smileList,
    required List<double> leftEyeList,
    required List<double> rightEyeList,
    required List<double> headYList,
    required List<double> headXList,
    required List<double> headZList,
  }) {
    final smileStd = calcStd(smileList);
    final leftEyeStd = calcStd(leftEyeList);
    final rightEyeStd = calcStd(rightEyeList);
    final headYStd = calcStd(headYList);
    final headXStd = calcStd(headXList);
    final headZStd = calcStd(headZList);
    final eyeStd = max(leftEyeStd, rightEyeStd);

    final isNeutral = isLikelyNeutral(
      smileStd: smileStd,
      eyeStd: eyeStd,
      headYStd: headYStd,
      headXStd: headXStd,
      headZStd: headZStd,
    );

    final smileChanges = countChangeFrames(
      smileList,
      threshold: smileFrameChangeThreshold,
    );
    final leftEyeChanges = countChangeFrames(
      leftEyeList,
      threshold: eyeFrameChangeThreshold,
    );
    final rightEyeChanges = countChangeFrames(
      rightEyeList,
      threshold: eyeFrameChangeThreshold,
    );
    final headYChanges = countChangeFrames(
      headYList,
      threshold: headYFrameChangeThreshold,
    );
    final headXChanges = countChangeFrames(
      headXList,
      threshold: headXFrameChangeThreshold,
    );
    final headZChanges = countChangeFrames(
      headZList,
      threshold: headZFrameChangeThreshold,
    );

    final eyeStill =
        leftEyeStd < eyeNeutralThreshold && rightEyeStd < eyeNeutralThreshold;
    final smileStill = smileStd < smileNeutralThreshold;
    if (eyeStill && smileStill) return false;

    int validSignals = 0;

    if (isNeutral) {
      if (smileStd > smileNeutralThreshold) validSignals++;
      if (eyeStd > eyeNeutralThreshold) validSignals++;
      if (headYStd > headYNeutralThreshold) validSignals++;
      if (headXStd > headXNeutralThreshold) validSignals++;
      if (headZStd > headZNeutralThreshold) validSignals++;
      return validSignals >= 1;
    }

    final hasSmileMovement =
        smileStd > smileStdThreshold && smileChanges >= smileFrameThreshold;
    final hasEyeMovement =
        (leftEyeStd > eyeStdThreshold || rightEyeStd > eyeStdThreshold) &&
        (leftEyeChanges >= eyeFrameThreshold ||
            rightEyeChanges >= eyeFrameThreshold);
    final hasHeadMovement =
        (headYStd > headYStdThreshold && headYChanges >= headYFrameThreshold) ||
        (headXStd > headXStdThreshold && headXChanges >= headXFrameThreshold) ||
        (headZStd > headZStdThreshold && headZChanges >= headZFrameThreshold);

    // ✅ شرط إضافي صارم: لو الصورة فيها تغييرات في الابتسامة فقط → ارفض
    if (smileChanges >= 10 &&
        leftEyeChanges == 0 &&
        rightEyeChanges == 0 &&
        headYChanges == 0 &&
        headXChanges == 0 &&
        headZChanges == 0) {
      debugPrint("❌ Refused: Only smile changes detected → likely spoof");
      return false;
    }

    if (hasSmileMovement && !hasEyeMovement && !hasHeadMovement) {
      debugPrint("❌ Refused: Only smile movement detected");
      return false;
    }

    if (smileChanges > 10 && smileStd < 0.02) {
      debugPrint(
        "❌ Refused: Suspicious smile variation without genuine spread",
      );
      return false;
    }

    if (hasHeadMovement && !hasSmileMovement && !hasEyeMovement) {
      final headStdLow = headYStd < 0.4 && headXStd < 0.4 && headZStd < 0.4;
      if (headStdLow) {
        debugPrint(
          "❌ Refused: Head movement detected but STD too low → likely fake",
        );
        return false;
      }
    }

    if (hasSmileMovement) validSignals++;
    if (hasEyeMovement) validSignals++;
    if (hasHeadMovement) validSignals++;

    debugPrint(
      "✅ Valid signals: $validSignals | Smile: $hasSmileMovement, Eye: $hasEyeMovement, Head: $hasHeadMovement",
    );

    // ✅ شرط قبول لو في حركة رأس + عين (حتى من غير ابتسامة)
    if ((hasHeadMovement && hasEyeMovement) || validSignals >= 2) {
      return true;
    }

    return false;
  }
}
