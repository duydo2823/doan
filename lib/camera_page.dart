import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  // Image File
  File? image;

  // Image Picker
  final picker = ImagePicker();

  // Pick Image Method
  Future<void> pickImage(ImageSource source) async {
    // Pick from camera or gallery
    final pickedFile = await picker.pickImage(source: source);

    // Update selected image
    if (pickedFile != null) {
      setState(() {
        image = File(pickedFile.path);
      });
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
          // Image display
          SizedBox(
          height: 300,
          width: 300,
          child: image != null
              ?
          // Image selected
          Image.file(image!)
              :
          // No image selected
          const Center(child: Text("No image selected")),
        ),
        // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Camera button
                ElevatedButton(
                  onPressed: () => pickImage(ImageSource.camera),
                  child: const Text("Camera"),
                ), // ElevatedButton

                // Gallery button
                ElevatedButton(
                  onPressed: () => pickImage(ImageSource.gallery),
                  child: const Text("Gallery"),
                ), // ElevatedButton
              ],
            ),
          ],
        ),
      ),
    );
  }
}
