import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../network/api_client.dart';

enum PhotoSource { camera, gallery }

/// Largest upload the server accepts (Vercel limits a request body to 4.5 MB).
const maxUploadBytes = 4 * 1024 * 1024;

/// Picks files into memory (bytes, so uploads work on the web). Behind an
/// interface so tests can hand back fixed bytes.
abstract interface class FilePickers {
  /// A photo from the camera (Android) or a file chooser (web). Null if cancelled.
  Future<UploadFile?> pickPhoto(PhotoSource source);

  /// A PDF. Null if cancelled. Photos go through [pickPhoto], which shrinks them.
  Future<UploadFile?> pickPdf();
}

class DeviceFilePickers implements FilePickers {
  final _images = ImagePicker();

  @override
  Future<UploadFile?> pickPhoto(PhotoSource source) async {
    final file = await _images.pickImage(
      source: source == PhotoSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      // Resized on the device: a 1600 px JPEG (~0.3-0.6 MB) reads as well as the
      // original and uploads fast; full camera photos (5-10 MB) exceed the server's
      // 4.5 MB request limit.
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final name = file.name.isEmpty ? 'photo.jpg' : file.name;
    return UploadFile(
      bytes: bytes,
      name: name,
      mimeType: file.mimeType ?? mimeTypeFor(name),
    );
  }

  @override
  Future<UploadFile?> pickPdf() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return UploadFile(
      bytes: bytes,
      name: file.name,
      mimeType: mimeTypeFor(file.name),
    );
  }
}

final filePickersProvider = Provider<FilePickers>((ref) => DeviceFilePickers());
