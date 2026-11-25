import 'dart:typed_data';
import 'package:flutter/foundation.dart';

void triggerWebDownload(Uint8List bytes, String fileName, String mimeType) {
  debugPrint('Web download not supported on non-web platform: $fileName');
}
