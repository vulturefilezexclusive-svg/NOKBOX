import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// Extracts a vivid accent colour from artwork using a small HSV histogram
/// (original implementation; no third-party palette code).
Future<Color?> extractAccentColor(ImageProvider provider, {int sample = 48}) async {
  try {
    final resized = ResizeImage(provider, width: sample, height: sample);
    final stream = resized.resolve(ImageConfiguration.empty);
    final completer = Completer<ui.Image>();
    late ImageStreamListener l;
    l = ImageStreamListener((info, _) {
      completer.complete(info.image);
      stream.removeListener(l);
    }, onError: (e, _) {
      if (!completer.isCompleted) completer.completeError(e);
      stream.removeListener(l);
    });
    stream.addListener(l);
    final img = await completer.future.timeout(const Duration(seconds: 3));
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    return accentFromRgba(data.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

/// Pure function (unit-tested): picks the most populated saturated hue bucket.
Color? accentFromRgba(Uint8List rgba) {
  const buckets = 36;
  final score = List<double>.filled(buckets, 0);
  final sumS = List<double>.filled(buckets, 0);
  final sumV = List<double>.filled(buckets, 0);
  final count = List<int>.filled(buckets, 0);
  final sumHx = List<double>.filled(buckets, 0);
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    final c = Color.fromARGB(255, rgba[i], rgba[i + 1], rgba[i + 2]);
    final hsv = HSVColor.fromColor(c);
    if (hsv.saturation < 0.25 || hsv.value < 0.2) continue;
    final b = (hsv.hue / 360 * buckets).floor() % buckets;
    score[b] += hsv.saturation * hsv.value;
    sumS[b] += hsv.saturation;
    sumV[b] += hsv.value;
    sumHx[b] += hsv.hue;
    count[b]++;
  }
  var best = -1;
  for (var b = 0; b < buckets; b++) {
    if (count[b] == 0) continue;
    if (best == -1 || score[b] > score[best]) best = b;
  }
  if (best == -1) return null;
  final n = count[best];
  final s = (sumS[best] / n).clamp(0.55, 1.0);
  final v = (sumV[best] / n).clamp(0.75, 1.0);
  return HSVColor.fromAHSV(1, sumHx[best] / n, s, v).toColor();
}
