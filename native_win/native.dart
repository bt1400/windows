// WINDOWS SÜRÜMÜ: sadece dosyadan yedek yükleme var; bildirim, parmak izi, konum yok.
import 'package:file_selector/file_selector.dart' as fs;

class NotifItem {
  final int id;
  final DateTime at;
  final String title, body;
  NotifItem(this.id, this.at, this.title, this.body);
}

class Nat {
  static const bool full = false;
  static const bool files = true;
  static const String ad = 'Windows';
  static Future<void> init() async {}
  static Future<void> reschedule(List<NotifItem> items) async {}
  static Future<bool> bioAvailable() async => false;
  static Future<bool> bioAuth(String reason) async => false;
  static Future<List<double>?> location() async => null;
  static Future<String?> pickJson() async {
    try {
      final f = await fs.openFile();
      if (f == null) return null;
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }
}
