import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../network/api_client.dart';

enum PhotoSource { camera, gallery }

/// Picks files into memory (bytes, so uploads work on the web). Behind an
/// interface so tests can hand back fixed bytes.
abstract interface class FilePickers {
  /// A photo from the camera (Android) or a file chooser (web). Null if cancelled.
  Future<UploadFile?> pickPhoto(PhotoSource source);

  /// An image or PDF. Null if cancelled.
  Future<UploadFile?> pickImageOrPdf();
}

class DeviceFilePickers implements FilePickers {
  final _images = ImagePicker();

  @override
  Future<UploadFile?> pickPhoto(PhotoSource source) async {
    final file = await _images.pickImage(
      source: source == PhotoSource.camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 85,
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
  Future<UploadFile?> pickImageOrPdf() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return UploadFile(bytes: bytes, name: file.name, mimeType: mimeTypeFor(file.name));
  }
}

final filePickersProvider = Provider<FilePickers>((ref) => DeviceFilePickers());
