import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

/// Pure mask->alpha transform (unit-tested).
/// mask >= 128 -> alpha 255 (object), else alpha 0 (transparent).
Uint8List applyMaskToAlpha(Uint8List rgbPngBytes, Uint8List maskPngBytes) {
  final rgb = img.decodeImage(rgbPngBytes);
  final mask = img.decodeImage(maskPngBytes);
  if (rgb == null || mask == null) return rgbPngBytes;
  final resizedMask = (mask.width != rgb.width || mask.height != rgb.height)
      ? img.copyResize(mask, width: rgb.width, height: rgb.height)
      : mask;
  final out = img.Image(width: rgb.width, height: rgb.height, numChannels: 4);
  for (int y = 0; y < rgb.height; y++) {
    for (int x = 0; x < rgb.width; x++) {
      final rp = rgb.getPixel(x, y);
      final mp = resizedMask.getPixel(x, y);
      final m = mp.r.toInt();
      out.setPixelRgba(
        x,
        y,
        rp.r.toInt(),
        rp.g.toInt(),
        rp.b.toInt(),
        m >= 128 ? 255 : 0,
      );
    }
  }
  return Uint8List.fromList(img.encodePng(out));
}

class CutoutResult {
  final Uint8List pngBytes;
  final bool usedCutout;
  const CutoutResult(this.pngBytes, this.usedCutout);
}

class _CutoutJob {
  final Uint8List sourceBytes;
  final Uint8List? maskBytes;
  final double x, y, w, h;
  const _CutoutJob({
    required this.sourceBytes,
    required this.maskBytes,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });
}

CutoutResult _runCutout(_CutoutJob job) {
  final src = img.decodeImage(job.sourceBytes);
  if (src == null) return CutoutResult(job.sourceBytes, false);
  final padX = (src.width * job.w * 0.02).round();
  final padY = (src.height * job.h * 0.02).round();
  int cropX = (src.width * job.x).round() - padX;
  int cropY = (src.height * job.y).round() - padY;
  int cropW = (src.width * job.w).round() + padX * 2;
  int cropH = (src.height * job.h).round() + padY * 2;
  if (cropX < 0) cropX = 0;
  if (cropY < 0) cropY = 0;
  if (cropX + cropW > src.width) cropW = src.width - cropX;
  if (cropY + cropH > src.height) cropH = src.height - cropY;
  if (cropW <= 0 || cropH <= 0) return CutoutResult(job.sourceBytes, false);

  final cropped = img.copyCrop(
    src,
    x: cropX,
    y: cropY,
    width: cropW,
    height: cropH,
  );

  img.Image result = cropped;
  bool usedCutout = false;
  if (job.maskBytes != null) {
    final mask = img.decodeImage(job.maskBytes!);
    if (mask != null) {
      final maskCrop = img.copyCrop(
        mask.width == src.width && mask.height == src.height
            ? mask
            : img.copyResize(mask, width: src.width, height: src.height),
        x: cropX,
        y: cropY,
        width: cropW,
        height: cropH,
      );
      final rgbaMask = img.copyResize(
        maskCrop,
        width: cropped.width,
        height: cropped.height,
      );
      final out = img.Image(
        width: cropped.width,
        height: cropped.height,
        numChannels: 4,
      );
      for (int py = 0; py < cropped.height; py++) {
        for (int px = 0; px < cropped.width; px++) {
          final rp = cropped.getPixel(px, py);
          final mp = rgbaMask.getPixel(px, py);
          out.setPixelRgba(
            px,
            py,
            rp.r.toInt(),
            rp.g.toInt(),
            rp.b.toInt(),
            mp.r.toInt() >= 128 ? 255 : 0,
          );
        }
      }
      result = out;
      usedCutout = true;
    }
  }

  // Resize to max 900px on the longest side.
  if (result.width > 900 || result.height > 900) {
    if (result.width >= result.height) {
      result = img.copyResize(result, width: 900);
    } else {
      result = img.copyResize(result, height: 900);
    }
  }

  if (usedCutout) {
    return CutoutResult(Uint8List.fromList(img.encodePng(result)), true);
  }
  return CutoutResult(
    Uint8List.fromList(img.encodeJpg(result, quality: 88)),
    false,
  );
}

/// Runs in a background isolate via compute(); payload is bytes + bbox only.
class SegmentationService {
  Future<CutoutResult> makeCutout({
    required Uint8List sourceBytes,
    required Uint8List? maskBytes,
    required double x,
    required double y,
    required double w,
    required double h,
  }) {
    return compute(
      _runCutout,
      _CutoutJob(
        sourceBytes: sourceBytes,
        maskBytes: maskBytes,
        x: x,
        y: y,
        w: w,
        h: h,
      ),
    );
  }
}

/// Download bytes from a URL (used for masks). Returns null on failure.
Future<Uint8List?> fetchBytes(String url) async {
  if (url.isEmpty) return null;
  try {
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) return null;
    return res.bodyBytes;
  } catch (_) {
    return null;
  }
}
