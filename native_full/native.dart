// TAM SÜRÜM: telefon bildirimi, parmak izi, GPS konumu, dosyadan yedek yükleme.
import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:local_auth/local_auth.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotifItem {
  final int id;
  final DateTime at;
  final String title, body;
  NotifItem(this.id, this.at, this.title, this.body);
}

class Nat {
  static const bool full = true;
  static const bool files = true;
  static const String ad = 'tam';
  static final FlutterLocalNotificationsPlugin _np = FlutterLocalNotificationsPlugin();
  static final LocalAuthentication _la = LocalAuthentication();
  static bool _ok = false;

  static Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));
      await _np.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      await _np.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      _ok = true;
    } catch (_) {
      _ok = false;
    }
  }

  static Future<void> reschedule(List<NotifItem> items) async {
    if (!_ok) return;
    try {
      await _np.cancelAll();
      const det = NotificationDetails(
          android: AndroidNotificationDetails('hatirlatma', 'Hatırlatmalar',
              channelDescription: 'Çek, belge, ödeme sözü, bakım ve alacak hatırlatmaları', importance: Importance.high, priority: Priority.high));
      final now = tz.TZDateTime.now(tz.local);
      for (final n in items) {
        final t = tz.TZDateTime.from(n.at, tz.local);
        if (t.isBefore(now)) continue;
        await _np.zonedSchedule(n.id, n.title, n.body, t, det,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle, uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime);
      }
    } catch (_) {}
  }

  static Future<bool> bioAvailable() async {
    try {
      return await _la.canCheckBiometrics && (await _la.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> bioAuth(String reason) async {
    try {
      return await _la.authenticate(localizedReason: reason, options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true));
    } catch (_) {
      return false;
    }
  }

  static Future<List<double>?> location() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 25)));
      return [p.latitude, p.longitude];
    } catch (_) {
      return null;
    }
  }

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
