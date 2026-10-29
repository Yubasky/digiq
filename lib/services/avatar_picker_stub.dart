// lib/services/avatar_picker_stub.dart

import 'dart:typed_data';

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
  return null;
}

