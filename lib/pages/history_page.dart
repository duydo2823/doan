import 'dart:io';
import 'package:flutter/material.dart';
import '../services/history_storage.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Map<String, dynamic>> _records = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await DetectionHistoryStorage.getAll();
    setState(() => _records = data.reversed.toList());
  }

  Future<void> _clear() async {
    await DetectionHistoryStorage.clear();
    setState(() => _records = []);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🗑 Đã xoá toàn bộ lịch sử.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch sử nhận diện'),
        backgroundColor: const Color(0xFF43A047),
        actions: [
          if (_records.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_forever),
              onPressed: _clear,
            )
        ],
      ),
      body: _records.isEmpty
          ? const Center(child: Text('Chưa có dữ liệu lịch sử.'))
          : ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _records.length,
        itemBuilder: (_, i) {
          final r = _records[i];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: ListTile(
              leading: r['path'] != null && File(r['path']).existsSync()
                  ? ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(File(r['path']),
                    width: 60, height: 60, fit: BoxFit.cover),
              )
                  : const Icon(Icons.image_not_supported, size: 40),
              title: Text('${r['cls']} (${r['score']})'),
              subtitle: Text('🕒 ${r['time']}\n⏱ ${r['latency']} ms'),
            ),
          );
        },
      ),
    );
  }
}
