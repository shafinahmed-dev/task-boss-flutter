import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> deliverFile({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  BuildContext? context,
}) async {
  try {
    final tempDir = await getTemporaryDirectory();
    final filePath = '${tempDir.path}/$fileName';
    final file = XFile.fromData(bytes, name: fileName, mimeType: mimeType);
    await file.saveTo(filePath);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(filePath, mimeType: mimeType, name: fileName)],
        subject: 'Document: $fileName',
      ),
    );

    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$fileName ready for share/save')),
      );
    }
  } catch (e) {
    debugPrint('File delivery failed on mobile/desktop: $e');
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to share file: $e')),
      );
    }
  }
}

void triggerWebDownload(Uint8List bytes, String fileName, String mimeType) {
  debugPrint('Web download not supported on non-web platform: $fileName');
}
