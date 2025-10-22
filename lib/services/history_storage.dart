import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class DetectionHistoryStorage {
  static const _key = 'detection_history';

  /// Lưu 1 bản ghi (dạng Map) vào danh sách
  static Future<void> addRecord(Map<String, dynamic> record) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    list.add(jsonEncode(record));
    await prefs.setStringList(_key, list);
  }

  /// Lấy toàn bộ lịch sử
  static Future<List<Map<String, dynamic>>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    return list.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
  }

  /// Xoá toàn bộ lịch sử
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
