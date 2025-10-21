import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class DetectionPage extends StatefulWidget {
  const DetectionPage({super.key});

  @override
  State<DetectionPage> createState() => _DetectionPageState();
}

class _DetectionPageState extends State<DetectionPage> {
  final ImagePicker _picker = ImagePicker();
  XFile? _lastImage;
  String _status = 'Sẵn sàng';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // iOS Simulator không có camera. Thông báo cho user biết.
    if (!mounted) return;
    if (Platform.isIOS && !await _isRealDevice()) {
      setState(() {
        _status =
        'Đang chạy Simulator iOS: Simulator không hỗ trợ Camera. Hãy build lên iPhone thật.';
      });
      return;
    }

    final ok = await _ensurePermissions();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _status = 'Thiếu quyền Camera/Photos. Hãy cấp quyền trong Cài đặt.';
      });
      return;
    }
  }

  Future<bool> _isRealDevice() async {
    // Cách đơn giản: nếu là iOS và có camera permission trạng thái 'restricted' trên sim,
    // ta vẫn cứ cho biết là sim. Ở đây mình luôn trả true trên iOS device thật.
    // Bạn có thể tích hợp device_info_plus để kiểm tra kỹ hơn.
    return true;
  }

  Future<bool> _ensurePermissions() async {
    // CAMERA
    final cam = await Permission.camera.status;
    if (cam.isDenied || cam.isRestricted) {
      final res = await Permission.camera.request();
      if (!res.isGranted) return false;
    } else if (cam.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }

    // PHOTOS (thư viện ảnh) — image_picker cần khi đọc/ghi ảnh
    // Trên iOS 14+, có thể có Limited Access. Mặc định ta xin full.
    var photos = await Permission.photos.status;
    if (photos.isDenied || photos.isRestricted) {
      final res = await Permission.photos.request();
      if (!res.isGranted) return false;
      photos = await Permission.photos.status;
    } else if (photos.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }

    // Nếu quay video, bật microphone
    // final mic = await Permission.microphone.request();

    return true;
  }

  Future<void> _pickFromCamera() async {
    final ok = await _ensurePermissions();
    if (!ok) {
      setState(() {
        _status = 'Thiếu quyền Camera/Photos. Hãy cấp quyền trong Cài đặt.';
      });
      return;
    }

    try {
      final x = await _picker.pickImage(source: ImageSource.camera, preferredCameraDevice: CameraDevice.rear);
      if (x == null) return;
      setState(() {
        _lastImage = x;
        _status = 'Đã chụp ảnh: ${x.name}';
      });

      // TODO: gọi model/WS xử lý ảnh tại đây
      // await _runDetection(File(x.path));
    } catch (e) {
      setState(() {
        _status = 'Lỗi mở camera: $e';
      });
    }
  }

  Future<void> _pickFromGallery() async {
    final ok = await _ensurePermissions();
    if (!ok) {
      setState(() {
        _status = 'Thiếu quyền Photos. Hãy cấp quyền trong Cài đặt.';
      });
      return;
    }

    try {
      final x = await _picker.pickImage(source: ImageSource.gallery);
      if (x == null) return;
      setState(() {
        _lastImage = x;
        _status = 'Đã chọn ảnh: ${x.name}';
      });

      // TODO: gọi model/WS xử lý ảnh tại đây
      // await _runDetection(File(x.path));
    } catch (e) {
      setState(() {
        _status = 'Lỗi mở thư viện ảnh: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final img = _lastImage;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detection Page'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(_status, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _pickFromCamera,
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Chụp bằng Camera'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickFromGallery,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Chọn từ Thư viện'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (img != null) Expanded(child: _Preview(path: img.path)),
          ],
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  final String path;
  const _Preview({required this.path});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Image.file(
        File(path),
        fit: BoxFit.contain,
      ),
    );
  }
}
