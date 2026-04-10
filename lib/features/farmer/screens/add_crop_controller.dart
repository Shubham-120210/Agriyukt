import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

class AddCropController extends ChangeNotifier {
  File? _selectedImage;
  File? get selectedImage => _selectedImage;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  final ImagePicker _picker = ImagePicker();

  // 📸 1. Pick, Crop, and Compress Flow
  Future<void> pickAndProcessImage(ImageSource source) async {
    try {
      _isLoading = true;
      notifyListeners();

      // Step A: Pick Image
      final XFile? pickedFile = await _picker.pickImage(source: source);
      if (pickedFile == null) {
        _isLoading = false;
        notifyListeners();
        return; // User canceled
      }

      File imageFile = File(pickedFile.path);

      // Step B: Crop Image
      File? croppedFile = await _cropImage(imageFile);
      if (croppedFile == null) {
        _isLoading = false;
        notifyListeners();
        return; // User backed out of cropper
      }

      // Step C: Compress Image
      File? compressedFile = await _compressImage(croppedFile);

      _selectedImage = compressedFile ?? croppedFile;
    } catch (e) {
      debugPrint("Error processing image: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ✂️ 2. The Cropper UI
  Future<File?> _cropImage(File imageFile) async {
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: imageFile.path,
      compressQuality: 100, // We compress later
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Edit Crop Photo',
          toolbarColor: Colors.green,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: false,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: 'Edit Crop Photo',
        ),
      ],
    );
    return croppedFile != null ? File(croppedFile.path) : null;
  }

  // 🗜️ 3. The Compressor (Makes uploads lightning fast)
  Future<File?> _compressImage(File file) async {
    final dir = await getTemporaryDirectory();
    final targetPath =
        '${dir.absolute.path}/temp_${DateTime.now().millisecondsSinceEpoch}.jpg';

    var result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 70, // Shrinks size drastically without losing visual quality
      minWidth: 800,
      minHeight: 800,
    );

    return result != null ? File(result.path) : null;
  }

  void clearImage() {
    _selectedImage = null;
    notifyListeners();
  }
}
