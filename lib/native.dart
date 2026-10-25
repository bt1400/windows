// TEMEL SÜRÜM: bildirim / parmak izi / konum / dosya seçici yok.
// Tam sürümde bu dosyanın yerine native_full/native.dart kullanılır.
class NotifItem {
  final int id;
  final DateTime at;
  final String title, body;
  NotifItem(this.id, this.at, this.title, this.body);
}

class Nat {
  static const bool full = false;
  static const bool files = false;
  static const String ad = 'temel';
  static Future<void> init() async {}
  static Future<void> reschedule(List<NotifItem> items) async {}
  static Future<bool> bioAvailable() async => false;
  static Future<bool> bioAuth(String reason) async => false;
  static Future<List<double>?> location() async => null;
  static Future<String?> pickJson() async => null;
}
