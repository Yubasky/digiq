// lib/services/avatar_picker_web.dart

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

class PickedAvatarFile {
  final Uint8List bytes;
  final String extension;
  final String mimeType;
  final int sizeInBytes;

  const PickedAvatarFile({
    required this.bytes,
    required this.extension,
    required this.mimeType,
    required this.sizeInBytes,
  });
}

Future<PickedAvatarFile?> pickAvatarImage() async {
  final completer = Completer<PickedAvatarFile?>();
  final input = web.document.createElement('input') as web.HTMLInputElement;
  input.type = 'file';
  input.accept = 'image/jpeg,image/png,image/webp';

  input.onChange.listen((e) {
    final files = input.files;
    if (files == null || files.length == 0) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }

    final file = files.item(0)!;
    final name = file.name;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'jpg';
    final mime = file.type.isNotEmpty ? file.type : 'image/$ext';
    final size = file.size;

    final reader = web.FileReader();
    reader.onLoadEnd.listen((e) {
      try {
        final result = reader.result;
        if (result != null) {
          final jsBuffer = result as JSArrayBuffer;
          final uint8List = jsBuffer.toDart.asUint8List();
          if (!completer.isCompleted) {
            completer.complete(PickedAvatarFile(
              bytes: uint8List,
              extension: ext,
              mimeType: mime,
              sizeInBytes: size,
            ));
          }
        } else {
          if (!completer.isCompleted) completer.complete(null);
        }
      } catch (err) {
        if (!completer.isCompleted) completer.complete(null);
      }
    });

    reader.readAsArrayBuffer(file);
  });

  input.click();
  return completer.future;
}

