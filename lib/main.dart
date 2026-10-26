import 'dart:convert';
import 'dart:async' show Timer;
import 'dart:io' show Directory, File, Platform;
import 'dart:math' show Random;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'native.dart';

typedef R = Map<String, String>;

const aylar = ['Tümü', 'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
const navy = Color(0xFF1F2937);
const amber = Color(0xFFE8A13A);
const bg = Color(0xFFF4F5F7);
const line = Color(0xFFE5E7EB);
const gold = Color(0xFFF59E0B);
const goldBg = Color(0xFFFFF8E6);
const green = Color(0xFF16A34A);
const red = Color(0xFFDC2626);
const orange = Color(0xFFEA580C);
const blue = Color(0xFF2563EB);
const grey = Color(0xFF6B7280);
const bgDark = Color(0xFF0F172A);
const cardDark = Color(0xFF1F2937);
const lineDark = Color(0xFF374151);
bool darkMode = false;
Color get inkNavy => darkMode ? amber : navy;
bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
Color cardC(BuildContext c) => isDark(c) ? cardDark : Colors.white;
Color lineC(BuildContext c) => isDark(c) ? lineDark : line;

// ============================ YARDIMCILAR ============================
double toD(String? s) => double.tryParse((s ?? '').replaceAll(',', '.')) ?? 0;
double qty(String s) {
  if (s.contains(':')) {
    final p = s.split(':');
    return toD(p[0]) + toD(p.length > 1 ? p[1] : '0') / 60;
  }
  return toD(s);
}

String f2(double x) => (x - x.roundToDouble()).abs() < 1e-6
    ? x.round().toString()
    : x.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
String tl(double v, [String s = '₺']) {
  final neg = v < 0;
  v = v.abs();
  final p = v.toStringAsFixed(v.roundToDouble() == v ? 0 : 2).split('.');
  p[0] = p[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');
  return '${neg ? '-' : ''}${p.join(',')} $s';
}

String hm(double h) {
  final m = (h * 60).round();
  return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')} sa';
}

String norm(String s) {
  const a = 'İIıÇçĞğÖöŞşÜü';
  const b = 'iiiccggoossuu';
  final o = StringBuffer();
  for (final ch in s.split('')) {
    final i = a.indexOf(ch);
    o.write(i >= 0 ? b[i] : ch);
  }
  return o.toString().toLowerCase().trim();
}

String dshow(String? iso) => (iso != null && iso.length >= 10) ? '${iso.substring(8, 10)}.${iso.substring(5, 7)}.${iso.substring(0, 4)}' : (iso ?? '');
String dparse(String s) {
  final p = s.trim().split('.');
  if (p.length == 3 && p[2].length == 4) return '${p[2]}-${p[1].padLeft(2, '0')}-${p[0].padLeft(2, '0')}';
  return s.trim();
}

String nowHm() {
  final d = DateTime.now();
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String todayIso() => DateTime.now().toIso8601String().substring(0, 10);
int mon(R r) => int.tryParse((r['tarih'] ?? '').length >= 7 ? r['tarih']!.substring(5, 7) : '') ?? 0;
double borc(R r) => qty(r['miktar'] ?? '') * toD(r['ucret']);
double sum(Iterable<R> l, double Function(R) f) => l.fold(0.0, (a, r) => a + f(r));
int cmpDate(R a, R b) => (a['tarih'] ?? '').compareTo(b['tarih'] ?? '');
int daysSince(String? iso) {
  final d = DateTime.tryParse(iso ?? '');
  return d == null ? 0 : DateTime.now().difference(d).inDays;
}

void msg(BuildContext c, String t) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(t)));
void push(BuildContext c, Widget w) => Navigator.push(c, MaterialPageRoute(builder: (_) => w));
Color signC(double v) => v < 0 ? red : (v > 0 ? green : grey);

const durumAd = {'hic': 'Hiç ödemedi', 'kismen': 'Kısmen ödedi', 'tam': 'Tamamını ödedi', 'yok': 'İş kaydı yok'};
const durumRenk = {'hic': red, 'kismen': orange, 'tam': green, 'yok': grey};

// ============================ DEPO (JSON) ============================
class JobProfit {
  final double gelir, yakit, bakim, genel;
  JobProfit(this.gelir, this.yakit, this.bakim, this.genel);
  double get net => gelir - yakit - bakim - genel;
  double get marj => gelir > 0 ? net / gelir * 100 : 0;
}

bool mzOde(R r) => r['mz'] == '1' || norm(r['kalem'] ?? '').contains('mazot');

List<R> defaultTurler() => <R>[
      {'id': 'c', 'ad': 'Çalıştı', 'kisa': 'Ç', 'renk': '2', 'deger': '1', 'ucretli': '1'},
      {'id': 'y', 'ad': 'Yarım gün', 'kisa': '½', 'renk': '3', 'deger': '0.5', 'ucretli': '1'},
      {'id': 'g', 'ad': 'Gelmedi', 'kisa': 'G', 'renk': '0', 'deger': '0', 'ucretli': '0'},
      {'id': 'i', 'ad': 'Yıllık izin', 'kisa': 'Yİ', 'renk': '1', 'deger': '0', 'ucretli': '1'},
      {'id': 'r', 'ad': 'Raporlu', 'kisa': 'R', 'renk': '4', 'deger': '0', 'ucretli': '0'},
      {'id': 'h', 'ad': 'Hastane', 'kisa': 'H', 'renk': '6', 'deger': '0', 'ucretli': '0'},
      {'id': 't', 'ad': 'Hafta tatili', 'kisa': 'T', 'renk': '13', 'deger': '0', 'ucretli': '1'},
      {'id': 'm', 'ad': 'Mazeret izni', 'kisa': 'Mİ', 'renk': '5', 'deger': '0', 'ucretli': '1'},
      {'id': 'u', 'ad': 'Ücretsiz izin', 'kisa': 'Üİ', 'renk': '7', 'deger': '0', 'ucretli': '0'},
      {'id': 'f', 'ad': 'Fazla mesai', 'kisa': 'FM', 'renk': '10', 'deger': '1.5', 'ucretli': '1'},
    ];

const gunAd = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
const gunUzun = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];

String dstr(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class CStat {
  final String name;
  double borc = 0, alinan = 0, yil = 0;
  int n = 0;
  String? last, oldest;
  CStat(this.name);
  double get kalan => borc - alinan;
  String get durum => (borc <= 0 && alinan <= 0) ? 'yok' : (alinan <= 0 ? 'hic' : (kalan <= 0.5 ? 'tam' : 'kismen'));
}

class BStat {
  final R r;
  double worked = 0;
  int days = 0;
  double? kalanSaat;
  int? kalanGun;
  String durum = 'ok';
  BStat(this.r);
  String get makina => r['makina'] ?? '';
  String get tur => (r['tur'] ?? '').isEmpty ? 'Bakım' : r['tur']!;
  double get aralik => toD(r['aralik']);
  double get gun => toD(r['gun']);
  double get ratio {
    final a = aralik > 0 ? worked / aralik : 0.0, b = gun > 0 ? days / gun : 0.0;
    final m = a > b ? a : b;
    return m < 0 ? 0 : (m > 1 ? 1 : m);
  }
}

class MStat {
  final String name;
  double hrs = 0, trips = 0, litre = 0, gelir = 0, mazotTl = 0;
  MStat(this.name);
  double get kar => gelir - mazotTl;
  String get calisma => hrs > 0 ? hm(hrs) + (trips > 0 ? ' + ${f2(trips)} sefer' : '') : '${f2(trips)} sefer';
  double get lPerUnit => hrs > 0 ? litre / hrs : (trips > 0 ? litre / trips : 0);
  bool get active => hrs > 0 || trips > 0 || litre > 0 || gelir > 0;
}

class Store extends ChangeNotifier {
  List<R> isler = [], giderler = [], mazot = [];
  List<String> musteriler = [], makinalar = [];
  List<R> bakim = [];
  Map<String, String> telefon = {}, foto = {}, ayar = {}, gKat = {}, mKat = {}, renk = {};
  List<String> gKatList = [], mKatList = [];
  late File _f;
  Map<String, CStat>? _cs;
  List<CStat>? _top;

  // ---- İş fotoğrafları / kârlılık / puantaj ----
  List<R> isFoto = [], personel = [], puantaj = [], puanTur = [];
  Map<String, JobProfit>? _pf;

  void dropFotos(String id) {
    if (id.isEmpty) return;
    for (final f in isFoto.where((x) => x['is'] == id).toList()) {
      try {
        File(fp(f['yol'])).deleteSync();
      } catch (_) {}
    }
    isFoto.removeWhere((x) => x['is'] == id);
  }

  double mazotOde(int m) => sum(byMonth(giderler, m).where(mzOde), (r) => toD(r['tutar']));
  // Mazot borcu: alım/giriş tutarları (bilgi) - gidere "mazot ödemesi" olarak işlenenler
  double get mazotBorcu => sum(mazot.where((r) => r['tur'] != 'cikan'), (r) => toD(r['tutar'])) - sum(giderler.where(mzOde), (r) => toD(r['tutar']));

  R? turOf(String? id) {
    for (final t in puanTur) {
      if (t['id'] == id) return t;
    }
    return null;
  }

  R? markOf(String pid, String iso) {
    for (final r in puantaj) {
      if (r['pid'] == pid && r['tarih'] == iso) return r;
    }
    return null;
  }

  // Her işin gerçek kazancı: iş tutarı - yakıt payı - bakım payı - genel gider payı
  Map<String, JobProfit> get profit {
    if (_pf != null) return _pf!;
    final jobs = isler.where((r) => borc(r) > 0 && (r['tarih'] ?? '').length >= 7).toList();
    final mm = <String, double>{}, mo = <String, double>{};
    for (final r in jobs) {
      final ay = r['tarih']!.substring(0, 7);
      final k = '${norm(r['makina'] ?? '')}|$ay';
      mm[k] = (mm[k] ?? 0) + borc(r);
      mo[ay] = (mo[ay] ?? 0) + borc(r);
    }
    final fuel = <String, double>{}, bak = <String, double>{}, gen = <String, double>{};
    for (final r in mazot) {
      final t = r['tarih'] ?? '';
      if (r['tur'] == 'giren' || t.length < 7) continue;
      final k = '${norm(r['makina'] ?? '')}|${t.substring(0, 7)}';
      fuel[k] = (fuel[k] ?? 0) + ((r['tur'] == 'alim' && toD(r['tutar']) > 0) ? toD(r['tutar']) : toD(r['litre']) * avgPrice);
    }
    for (final r in bakim) {
      final t = r['tarih'] ?? '';
      if (t.length < 7) continue;
      final k = '${norm(r['makina'] ?? '')}|${t.substring(0, 7)}';
      bak[k] = (bak[k] ?? 0) + toD(r['tutar']);
    }
    if (ayar['genel_gider'] != '0') {
      for (final r in giderler) {
        final t = r['tarih'] ?? '';
        if (mzOde(r) || t.length < 7) continue;
        gen[t.substring(0, 7)] = (gen[t.substring(0, 7)] ?? 0) + toD(r['tutar']);
      }
    }
    final out = <String, JobProfit>{};
    for (final r in jobs) {
      final ay = r['tarih']!.substring(0, 7);
      final k = '${norm(r['makina'] ?? '')}|$ay';
      final b = borc(r);
      final sh = (mm[k] ?? 0) > 0 ? b / mm[k]! : 0.0;
      final gs = (mo[ay] ?? 0) > 0 ? b / mo[ay]! : 0.0;
      out[r['id'] ?? ''] = JobProfit(b, (fuel[k] ?? 0) * sh, (bak[k] ?? 0) * sh, (gen[ay] ?? 0) * gs);
    }
    return _pf = out;
  }

  // ---- v10: çek/senet, belgeler, avans, ödeme sözü, PIN ----
  List<R> cek = [], belge = [], avans = [];
  Map<String, String> soz = {};
  String get pin => ayar['pin'] ?? '';

  // Aynı müşteri+makina için son kullanılan birim ücret (yoksa makinanın son ücreti)
  String? lastUcret(String m, String k) {
    String? best, bestK;
    var bd = '', bdk = '';
    for (final r in isler) {
      if (toD(r['ucret']) <= 0 || norm(r['makina'] ?? '') != norm(k)) continue;
      final d = r['tarih'] ?? '';
      if (norm(r['musteri'] ?? '') == norm(m) && d.compareTo(bd) >= 0) {
        best = r['ucret'];
        bd = d;
      }
      if (d.compareTo(bdk) >= 0) {
        bestK = r['ucret'];
        bdk = d;
      }
    }
    return best ?? bestK;
  }

  List<R> get cekUyari => cek.where((r) => (r['durum'] ?? 'bekliyor') == 'bekliyor' && gunKala(r['vade']) <= 7).toList();
  List<R> get belgeUyari => belge.where((r) => gunKala(r['bitis']) <= 30).toList();
  List<CStat> get sozGelen => cust.values.where((s) {
        final v = soz[norm(s.name)];
        return v != null && v.length >= 10 && s.kalan > 0.5 && gunKala(v.substring(0, 10)) <= 0;
      }).toList();

  Future<void> load() async {
    final dir = (Platform.isWindows || Platform.isMacOS || Platform.isLinux) ? await getApplicationSupportDirectory() : await getApplicationDocumentsDirectory();
    docsDir = dir.path;
    _f = File('${dir.path}/veri_v2.json');
    String raw;
    if (await _f.exists()) {
      raw = await _f.readAsString();
    } else {
      raw = await rootBundle.loadString('assets/data.json');
      await _f.writeAsString(raw);
    }
    _parse(raw);
  }

  void _parse(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    List<R> lr(String k) => ((j[k] ?? []) as List).map((e) => R.from(e as Map)).toList();
    final a = lr('isler'), b = lr('giderler'), c = lr('mazot');
    final d = List<String>.from(j['musteriler'] ?? []), e = List<String>.from(j['makinalar'] ?? []);
    isler = a;
    giderler = b;
    mazot = c;
    musteriler = d;
    makinalar = e;
    Map<String, String> lm(String k) => Map<String, String>.from((j[k] ?? {}) as Map);
    bakim = lr('bakim');
    telefon = lm('telefon');
    foto = lm('foto');
    ayar = lm('ayar');
    gKat = lm('gkat');
    mKat = lm('mkat');
    renk = lm('renk');
    gKatList = List<String>.from(j['gkatl'] ?? []);
    mKatList = List<String>.from(j['mkatl'] ?? []);
    isFoto = lr('isfoto');
    personel = lr('personel');
    puantaj = lr('puantaj');
    puanTur = lr('puantur');
    if (puanTur.isEmpty) puanTur = defaultTurler();
    cek = lr('cek');
    belge = lr('belge');
    avans = lr('avans');
    soz = lm('soz');
  }

  String export() => jsonEncode({'isler': isler, 'giderler': giderler, 'mazot': mazot, 'musteriler': musteriler, 'makinalar': makinalar, 'bakim': bakim, 'telefon': telefon, 'foto': foto, 'ayar': ayar, 'gkat': gKat, 'mkat': mKat, 'renk': renk, 'gkatl': gKatList, 'mkatl': mKatList, 'isfoto': isFoto, 'personel': personel, 'puantaj': puantaj, 'puantur': puanTur, 'cek': cek, 'belge': belge, 'avans': avans, 'soz': soz});
  void commit() {
    _cs = null;
    _top = null;
    _pf = null;
    notifyListeners();
    planlaBildirim();
    _f.writeAsString(export());
  }

  Future<void> loadFrom(String asset) async {
    final a = Map<String, String>.from(ayar);
    _parse(await rootBundle.loadString(asset));
    if (a.isNotEmpty) ayar = a;
    commit();
  }

  Future<void> reset() => loadFrom('assets/excel_data.json');
  Future<void> clearAll() => loadFrom('assets/data.json');

  bool restore(String raw) {
    try {
      _parse(raw);
      commit();
      return true;
    } catch (_) {
      return false;
    }
  }

  String id() => 'u${DateTime.now().microsecondsSinceEpoch}';

  void ensure(R r) {
    final m = (r['musteri'] ?? '').trim(), k = (r['makina'] ?? '').trim();
    if (m.isNotEmpty && !musteriler.any((x) => norm(x) == norm(m))) musteriler.add(m);
    if (k.isNotEmpty && !makinalar.any((x) => norm(x) == norm(k))) makinalar.add(k);
  }

  List<R> byMonth(List<R> l, int m) => m == 0 ? l : l.where((r) => mon(r) == m).toList();

  double get avgPrice {
    double t = 0, l = 0;
    for (final r in mazot) {
      if (r['tur'] != 'cikan' && toD(r['tutar']) > 0 && toD(r['litre']) > 0) {
        t += toD(r['tutar']);
        l += toD(r['litre']);
      }
    }
    return l == 0 ? 0 : t / l;
  }

  double get depo => sum(mazot.where((r) => r['tur'] == 'giren'), (r) => toD(r['litre'])) - sum(mazot.where((r) => r['tur'] == 'cikan'), (r) => toD(r['litre']));
  double alimTl(int m) => sum(byMonth(mazot, m).where((r) => r['tur'] != 'cikan'), (r) => toD(r['tutar']));

  String get year {
    var y = '${DateTime.now().year}';
    if (isler.any((r) => (r['tarih'] ?? '').startsWith(y))) return y;
    var best = '';
    for (final r in isler) {
      final t = r['tarih'] ?? '';
      if (t.length >= 4 && t.substring(0, 4).compareTo(best) > 0) best = t.substring(0, 4);
    }
    return best.isEmpty ? y : best;
  }

  // Müşteri istatistikleri: borç, alınan, durum, en eski ödenmemiş iş (FIFO)
  Map<String, CStat> get cust {
    if (_cs != null) return _cs!;
    final m = <String, CStat>{};
    for (final n in musteriler) {
      m[norm(n)] = CStat(n);
    }
    final byC = <String, List<R>>{};
    for (final r in isler) {
      final k = norm(r['musteri'] ?? '');
      (byC[k] ??= []).add(r);
      m.putIfAbsent(k, () => CStat((r['musteri'] ?? '').trim().isEmpty ? 'Belirsiz' : r['musteri']!.trim()));
    }
    final y = year;
    byC.forEach((k, l) {
      final s = m[k]!;
      l.sort(cmpDate);
      for (final r in l) {
        final b = borc(r);
        s.borc += b;
        s.alinan += toD(r['alinan']);
        if (b > 0) s.n++;
        final t = r['tarih'] ?? '';
        if (t.isNotEmpty && (s.last == null || t.compareTo(s.last!) > 0)) s.last = t;
        if (t.startsWith(y)) s.yil += b;
      }
      double cum = 0;
      for (final r in l) {
        final b = borc(r);
        if (b > 0) {
          cum += b;
          if (cum > s.alinan + 0.5) {
            s.oldest = r['tarih'];
            break;
          }
        }
      }
    });
    return _cs = m;
  }

  List<CStat> get top5 {
    if (_top != null) return _top!;
    final l = cust.values.where((s) => s.yil > 0).toList()..sort((a, b) => b.yil.compareTo(a.yil));
    return _top = l.take(5).toList();
  }

  int rank(String name) => top5.indexWhere((s) => norm(s.name) == norm(name));

  // Bakım hatırlatmaları: her (makina, bakım türü) için son kayıt, çalışma saati ve gün hesabı
  List<BStat> get bakimDurum {
    final latest = <String, R>{};
    for (final r in bakim) {
      final k = '${norm(r['makina'] ?? '')}|${norm(r['tur'] ?? '')}';
      final o = latest[k];
      if (o == null || cmpDate(r, o) >= 0) latest[k] = r;
    }
    final out = <BStat>[];
    for (final r in latest.values) {
      final b = BStat(r);
      final k = norm(b.makina);
      b.worked = sum(isler.where((x) => norm(x['makina'] ?? '') == k && (x['tarih'] ?? '').compareTo(r['tarih'] ?? '') > 0 && (x['miktar'] ?? '').contains(':')), (x) => qty(x['miktar'] ?? ''));
      b.days = daysSince(r['tarih']);
      if (b.aralik > 0) b.kalanSaat = b.aralik - b.worked;
      if (b.gun > 0) b.kalanGun = b.gun.round() - b.days;
      final ks = b.kalanSaat, kg = b.kalanGun;
      if (b.aralik <= 0 && b.gun <= 0) {
        b.durum = 'bilgi';
      } else if ((ks != null && ks <= 0) || (kg != null && kg <= 0)) {
        b.durum = 'gec';
      } else if ((ks != null && ks <= (b.aralik * 0.1 < 10 ? 10 : b.aralik * 0.1)) || (kg != null && kg <= 7)) {
        b.durum = 'yakin';
      }
      out.add(b);
    }
    int w(String d) => d == 'gec' ? 0 : (d == 'yakin' ? 1 : (d == 'ok' ? 2 : 3));
    out.sort((a, b) {
      final c = w(a.durum).compareTo(w(b.durum));
      return c != 0 ? c : b.ratio.compareTo(a.ratio);
    });
    return out;
  }

  int get alacakGun => int.tryParse(ayar['gec_gun'] ?? '') ?? 180;
  List<CStat> get gecAlacak => cust.values.where((s) => s.kalan > 0.5 && s.oldest != null && daysSince(s.oldest) >= alacakGun).toList()..sort((a, b) => a.oldest!.compareTo(b.oldest!));
  String gCat(String kalem) => gKat[norm(kalem)] ?? '';
  String mCat(String name) => mKat[norm(name)] ?? '';

  // Alacak yaşlandırma (en eski işten başlayarak ödeme düşülür): 0-30, 31-90, 91-180, 180+ gün
  List<double> get aging {
    final b = [0.0, 0.0, 0.0, 0.0];
    final byC = <String, List<R>>{};
    for (final r in isler) {
      (byC[norm(r['musteri'] ?? '')] ??= []).add(r);
    }
    byC.forEach((k, l) {
      l.sort(cmpDate);
      var paid = sum(l, (r) => toD(r['alinan']));
      for (final r in l) {
        final x = borc(r);
        if (x <= 0) continue;
        final un = paid >= x ? 0.0 : x - paid;
        paid = paid >= x ? paid - x : 0.0;
        if (un > 0.5) {
          final d = daysSince(r['tarih']);
          b[d <= 30 ? 0 : (d <= 90 ? 1 : (d <= 180 ? 2 : 3))] += un;
        }
      }
    });
    return b;
  }

  int get dueCount => bakimDurum.where((b) => b.durum == 'gec' || b.durum == 'yakin').length;

  List<MStat> makinaStat(int m) {
    final out = <MStat>[];
    final js = byMonth(isler, m), ms = byMonth(mazot, m);
    for (final name in makinalar) {
      final k = norm(name);
      final s = MStat(name);
      for (final r in js.where((r) => norm(r['makina'] ?? '') == k)) {
        final q = r['miktar'] ?? '';
        if (q.contains(':')) {
          s.hrs += qty(q);
        } else {
          s.trips += qty(q);
        }
        s.gelir += borc(r);
      }
      final mine = ms.where((r) => r['tur'] != 'giren' && norm(r['makina'] ?? '') == k);
      s.litre = sum(mine, (r) => toD(r['litre']));
      s.mazotTl = sum(mine, (r) => (r['tur'] == 'alim' && toD(r['tutar']) > 0) ? toD(r['tutar']) : toD(r['litre']) * avgPrice);
      out.add(s);
    }
    return out;
  }
}

String docsDir = '';
// Kayıtlı foto yolunu (eski mutlak yol olsa bile) bugünkü uygulama klasörüne çevirir
String fp(String? p) => (p == null || p.isEmpty) ? '' : '$docsDir/fotolar/${p.split(RegExp(r'[\\/]')).last}';

final S = Store();
final ayF = ValueNotifier<int>(0);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await S.load();
  await Nat.init();
  planlaBildirim();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: S,
        builder: (context, _) => MaterialApp(
          title: 'İş Takip',
          debugShowCheckedModeBanner: false,
          scrollBehavior: const MaterialScrollBehavior().copyWith(dragDevices: {ui.PointerDeviceKind.touch, ui.PointerDeviceKind.mouse, ui.PointerDeviceKind.stylus, ui.PointerDeviceKind.trackpad}),
          themeMode: S.ayar['tema'] == 'koyu' ? ThemeMode.dark : (S.ayar['tema'] == 'acik' ? ThemeMode.light : ThemeMode.system),
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: amber, brightness: Brightness.light),
            scaffoldBackgroundColor: bg,
            appBarTheme: const AppBarTheme(
                backgroundColor: navy, foregroundColor: Colors.white, elevation: 0, titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
            navigationBarTheme: NavigationBarThemeData(
                backgroundColor: Colors.white, indicatorColor: amber.withAlpha(70), labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: amber, brightness: Brightness.dark),
            scaffoldBackgroundColor: bgDark,
            appBarTheme: const AppBarTheme(
                backgroundColor: navy, foregroundColor: Colors.white, elevation: 0, titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
          ),
          builder: (context, child) {
            darkMode = Theme.of(context).brightness == Brightness.dark;
            return LockGate(
                child: LayoutBuilder(builder: (c, cons) {
              final w = S.ayar['pencere'] == 'dar' ? 560.0 : (S.ayar['pencere'] == 'orta' ? 1000.0 : 0.0);
              if (cons.maxWidth <= 760 || w == 0 || cons.maxWidth <= w) return child ?? const SizedBox();
              return Container(color: const Color(0xFFD1D5DB), child: Align(alignment: Alignment.topCenter, child: SizedBox(width: w, height: double.infinity, child: child ?? const SizedBox())));
            }));
          },
          home: const Home(),
        ),
      );
}

void Function(int)? goTab;

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int i = 0;
  @override
  void initState() {
    super.initState();
    goTab = (v) => setState(() => i = v);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final due = S.bakimDurum.where((b) => b.durum == 'gec').toList();
      final gec = S.gecAlacak, ck = S.cekUyari, bl = S.belgeUyari, sg = S.sozGelen;
      if ((due.isNotEmpty || gec.isNotEmpty || ck.isNotEmpty || bl.isNotEmpty || sg.isNotEmpty) && mounted) {
        Widget h(String t) => Padding(padding: const EdgeInsets.only(top: 10, bottom: 2), child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)));
        showDialog(
            context: context,
            builder: (x) => AlertDialog(
                  title: const Text('🔔 Hatırlatmalar'),
                  content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (gec.isNotEmpty) h('${S.alacakGun} günü geçen alacaklar (${gec.length} müşteri, ${tl(gec.fold<double>(0.0, (a, s) => a + s.kalan))})'),
                      for (final s in gec.take(5)) Text('• ${s.name} – ${tl(s.kalan)} (${daysSince(s.oldest)} gün)'),
                      if (sg.isNotEmpty) h('Ödeme sözü günü gelenler'),
                      for (final s in sg.take(5)) Text('• ${s.name} – ${tl(s.kalan)}'),
                      if (ck.isNotEmpty) h('Vadesi yaklaşan / geçen çek-senetler'),
                      for (final r in ck.take(5)) Text('• ${r['musteri'] ?? ''} ${tl(toD(r['tutar']))} – ${gunKala(r['vade']) < 0 ? '${-gunKala(r['vade'])} gün geçti' : '${gunKala(r['vade'])} gün kaldı'}'),
                      if (bl.isNotEmpty) h('Süresi dolan / dolmak üzere olan belgeler'),
                      for (final r in bl.take(5)) Text('• ${r['makina'] ?? ''} ${r['tur'] ?? ''} – ${gunKala(r['bitis']) < 0 ? 'süresi doldu' : '${gunKala(r['bitis'])} gün kaldı'}'),
                      if (due.isNotEmpty) h('Bakımı gelen araçlar'),
                      for (final b in due.take(5)) Text('• ${b.makina} – ${b.tur}'),
                    ]),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(x), child: const Text('Sonra')),
                    if (gec.isNotEmpty || sg.isNotEmpty)
                      TextButton(
                          onPressed: () {
                            Navigator.pop(x);
                            push(context, const TahsilatPage());
                          },
                          child: const Text('Tahsilat')),
                    if (ck.isNotEmpty)
                      TextButton(
                          onPressed: () {
                            Navigator.pop(x);
                            setState(() => i = 8);
                          },
                          child: const Text('Çekler')),
                    if (bl.isNotEmpty)
                      TextButton(
                          onPressed: () {
                            Navigator.pop(x);
                            push(context, const BelgePage());
                          },
                          child: const Text('Belgeler')),
                    if (due.isNotEmpty)
                      FilledButton(
                          onPressed: () {
                            Navigator.pop(x);
                            setState(() => i = 5);
                          },
                          child: const Text('Bakım')),
                  ],
                ));
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: i, children: [const OzetTab(), IslerTab(), MazotTab(), const MusteriTab(), const MakinaTab(), BakimTab(), GiderTab(), const PuantajTab(), const CekTab()]),
        bottomNavigationBar: ListenableBuilder(
          listenable: S,
          builder: (c, _) {
            final n = S.dueCount, g = S.gecAlacak.length;
            final items = <List<Object>>[
              [Icons.dashboard_outlined, Icons.dashboard, 'Özet', 0],
              [Icons.agriculture_outlined, Icons.agriculture, 'İşler', 0],
              [Icons.local_gas_station_outlined, Icons.local_gas_station, 'Mazot', 0],
              [Icons.groups_outlined, Icons.groups, 'Müşteri', g],
              [Icons.precision_manufacturing_outlined, Icons.precision_manufacturing, 'Makina', S.belgeUyari.length],
              [Icons.build_circle_outlined, Icons.build_circle, 'Bakım', n],
              [Icons.payments_outlined, Icons.payments, 'Gider', 0],
              [Icons.event_available_outlined, Icons.event_available, 'Puantaj', 0],
              [Icons.request_page_outlined, Icons.request_page, 'Çek', S.cekUyari.length],
            ];
            return Material(
              color: cardC(context),
              elevation: 8,
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: 62,
                  child: LayoutBuilder(builder: (c0, cons) {
                    final itemW = cons.maxWidth >= items.length * 76 ? cons.maxWidth / items.length : 76.0;
                    return ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: items.length,
                    itemBuilder: (c, k) {
                      final it = items[k];
                      final on = k == i;
                      final cnt = it[3] as int;
                      return InkWell(
                        onTap: () => setState(() => i = k),
                        child: SizedBox(
                          width: itemW,
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Badge(isLabelVisible: cnt > 0, label: Text('$cnt'), child: Icon(on ? it[1] as IconData : it[0] as IconData, color: on ? inkNavy : grey)),
                            const SizedBox(height: 3),
                            Text(it[2] as String, style: TextStyle(fontSize: 10.5, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? inkNavy : grey)),
                            if (on) Container(margin: const EdgeInsets.only(top: 3), height: 3, width: 22, decoration: BoxDecoration(color: amber, borderRadius: BorderRadius.circular(2))),
                          ]),
                        ),
                      );
                    },
                  );
                  }),
                ),
              ),
            );
          },
        ),
      );
}

// ============================ ORTAK BİLEŞENLER ============================
class Box extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? color, border;
  final EdgeInsets pad;
  final double bottom;
  const Box({super.key, required this.child, this.onTap, this.color, this.border, this.pad = const EdgeInsets.all(14), this.bottom = 10});
  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final fill = color == null ? (d ? cardDark : Colors.white) : (d ? Color.alphaBlend(color!.withAlpha(40), cardDark) : color!);
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: border ?? (d ? lineDark : line), width: border == null ? 1 : 1.6)),
        child: InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap, child: Padding(padding: pad, child: child)),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String t;
  final Color c;
  const Pill(this.t, this.c, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: c.withAlpha(30), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
      );
}

class Avatar extends StatelessWidget {
  final String name;
  final IconData? icon;
  const Avatar(this.name, {super.key, this.icon});
  @override
  Widget build(BuildContext context) {
    const pal = [blue, green, orange, Color(0xFF7C3AED), Color(0xFF0891B2), Color(0xFFDB2777)];
    final col = pal[name.runes.fold(0, (a, b) => a + b) % pal.length];
    final t = name.trim();
    return CircleAvatar(
      radius: 20,
      backgroundColor: col.withAlpha(35),
      child: icon != null ? Icon(icon, color: col, size: 20) : Text(t.isEmpty ? '?' : String.fromCharCode(t.runes.first).toUpperCase(), style: TextStyle(color: col, fontWeight: FontWeight.w700)),
    );
  }
}

class StatCard extends StatelessWidget {
  final String label, value;
  final Color? color;
  final IconData? icon;
  const StatCard(this.label, this.value, {super.key, this.color, this.icon});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: cardC(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: lineC(context))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(children: [
            if (icon != null) Icon(icon, size: 15, color: color ?? grey),
            if (icon != null) const SizedBox(width: 4),
            Expanded(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: grey, fontSize: 12))),
          ]),
          const SizedBox(height: 6),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color))),
        ]),
      );
}

Widget two(String a, String b, {Color? ac, Color? bc}) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text(a, style: TextStyle(fontWeight: FontWeight.w700, color: ac)),
      Text(b, style: TextStyle(fontSize: 11.5, color: bc ?? grey)),
    ]);

Widget secTitle(String t, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Row(children: [
        Expanded(child: Text(t.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .6, color: grey))),
        if (trailing != null) trailing,
      ]),
    );

Widget searchBox(ValueChanged<String> f, String hint) => Builder(
    builder: (c) => TextField(
          onChanged: f,
          decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: hint,
              filled: true,
              fillColor: cardC(c),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: lineC(c))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: lineC(c)))),
        ));

Widget agePill(CStat s) {
  if (s.oldest == null || s.kalan <= 0.5) return const SizedBox();
  final d = daysSince(s.oldest);
  final col = d >= S.alacakGun ? red : (d > 60 ? orange : grey);
  return Pill('En eski ödenmemiş iş: ${dshow(s.oldest)} · $d gün', col);
}

class AyDrop extends StatelessWidget {
  const AyDrop({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
      valueListenable: ayF,
      builder: (_, v, __) => Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                dropdownColor: Colors.white,
                value: v,
                style: const TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.w600),
                items: [for (var i = 0; i < aylar.length; i++) DropdownMenuItem(value: i, child: Text(aylar[i]))],
                onChanged: (x) => ayF.value = x ?? 0,
              ),
            ),
          ));
}

Future<String?> pickKey(BuildContext c, String title, List<String> opts, String? cur) {
  var q = '';
  return showDialog<String>(
      context: c,
      builder: (_) => StatefulBuilder(builder: (ctx, set) {
            final k = norm(q);
            final l = opts.where((o) => k.isEmpty || norm(o).contains(k)).toList();
            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: double.maxFinite,
                height: 420,
                child: Column(children: [
                  TextField(autofocus: true, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Ara…'), onChanged: (v) => set(() => q = v)),
                  Expanded(
                    child: ListView(children: [
                      if (k.isEmpty) ListTile(leading: const Icon(Icons.clear_all), title: const Text('Tümü'), onTap: () => Navigator.pop(ctx, '')),
                      for (final o in l) ListTile(title: Text(o), selected: o == cur, onTap: () => Navigator.pop(ctx, o)),
                    ]),
                  ),
                ]),
              ),
            );
          }));
}

Future<String?> askName(BuildContext c, String title, [String init = '']) {
  final t = TextEditingController(text: init);
  return showDialog<String>(
      context: c,
      builder: (x) => AlertDialog(
            title: Text(title),
            content: TextField(controller: t, autofocus: true, decoration: const InputDecoration(border: OutlineInputBorder())),
            actions: [
              TextButton(onPressed: () => Navigator.pop(x), child: const Text('Vazgeç')),
              FilledButton(onPressed: () => Navigator.pop(x, t.text.trim()), child: const Text('Kaydet')),
            ],
          ));
}

// ============================ FORM ============================
class Fld {
  final String k, l, t; // t=metin, n=sayı, d=tarih, p=seçmeli yazı, s=açılır liste, m=çok satır
  final List<String> opts;
  final bool warn;
  const Fld(this.k, this.l, [this.t = 't', this.opts = const [], this.warn = false]);
}

const turler = ['giren=Depoya giriş', 'cikan=Makinaya yakıt (depodan)', 'alim=Dışarıdan alım'];

Future<R?> showForm(BuildContext c, String title, List<Fld> fl, R init, {bool canDelete = false}) =>
    showModalBottomSheet<R>(context: c, isScrollControlled: true, showDragHandle: true, builder: (_) => _FormSheet(title, fl, init, canDelete));

class _FormSheet extends StatefulWidget {
  final String title;
  final List<Fld> fl;
  final R init;
  final bool canDelete;
  const _FormSheet(this.title, this.fl, this.init, this.canDelete);
  @override
  State<_FormSheet> createState() => _FormState();
}

class _FormState extends State<_FormSheet> {
  final ctl = <String, TextEditingController>{};
  @override
  void initState() {
    super.initState();
    for (final f in widget.fl) {
      var v = widget.init[f.k] ?? '';
      if (f.t == 'd') v = dshow(v.isEmpty ? todayIso() : v);
      if (f.t == 's' && v.isEmpty) v = f.opts.first.split('=').first;
      ctl[f.k] = TextEditingController(text: v);
    }
  }

  Future<void> _save() async {
    final o = <String, String>{};
    for (final f in widget.fl) {
      var v = ctl[f.k]!.text.trim();
      if (f.warn && v.isNotEmpty) {
        final r = await confirmSimilar(context, v, f.opts, f.l.split(' ').first);
        if (r == null) return;
        v = r;
        ctl[f.k]!.text = r;
      }
      o[f.k] = f.t == 'd' ? dparse(v) : v;
    }
    if (!mounted) return;
    Navigator.pop(context, o);
  }

  void _auto() {
    if (widget.init['id'] != null) return;
    final u = ctl['ucret'];
    if (u == null || u.text.trim().isNotEmpty) return;
    final k = ctl['makina']?.text ?? '';
    if (k.trim().isEmpty) return;
    final v = S.lastUcret(ctl['musteri']?.text ?? '', k);
    if (v != null) u.text = v;
  }

  Widget _field(Fld f) {
    final c = ctl[f.k]!;
    if (f.t == 's') {
      return DropdownButtonFormField<String>(
        initialValue: c.text,
        decoration: InputDecoration(labelText: f.l, border: const OutlineInputBorder()),
        items: [for (final o in f.opts) DropdownMenuItem(value: o.split('=').first, child: Text(o.split('=').last))],
        onChanged: (v) => c.text = v ?? c.text,
      );
    }
    Widget? suf;
    if (f.t == 'p') {
      suf = PopupMenuButton<String>(
        icon: const Icon(Icons.arrow_drop_down),
        onSelected: (v) => setState(() {
          c.text = v;
          _auto();
        }),
        itemBuilder: (_) => [for (final o in f.opts) PopupMenuItem(value: o, child: Text(o))],
      );
    } else if (f.t == 'd') {
      suf = IconButton(
        icon: const Icon(Icons.event),
        onPressed: () async {
          final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040));
          if (d != null) setState(() => c.text = dshow(d.toIso8601String()));
        },
      );
    } else if (f.t == 'g') {
      suf = IconButton(
        icon: const Icon(Icons.my_location),
        tooltip: 'Şu anki konumu al',
        onPressed: () async {
          final l = await Nat.location();
          if (!mounted) return;
          if (l == null) {
            msg(context, Nat.full ? 'Konum alınamadı (izin verin, GPS\'i açın).' : 'Bu sürümde konum özelliği yok (temel sürüm).');
          } else {
            setState(() => c.text = '${l[0].toStringAsFixed(6)},${l[1].toStringAsFixed(6)}');
          }
        },
      );
    }
    final tf = TextField(
      controller: c,
      onChanged: f.t == 'p'
          ? (_) {
              setState(() {});
              _auto();
            }
          : null,
      keyboardType: f.t == 'n' ? const TextInputType.numberWithOptions(decimal: true) : (f.t == 'm' ? TextInputType.multiline : TextInputType.text),
      minLines: f.t == 'm' ? 2 : 1,
      maxLines: f.t == 'm' ? 5 : 1,
      decoration: InputDecoration(labelText: f.l, border: const OutlineInputBorder(), suffixIcon: suf),
    );
    if (f.t != 'p') return tf;
    final sg = c.text.trim().isEmpty ? <String>[] : similar(c.text, f.opts);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      tf,
      if (sg.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('Kayıtlı olanlar:', style: TextStyle(fontSize: 12, color: grey)),
            for (final x in sg) ActionChip(label: Text(x), onPressed: () => setState(() {
                  c.text = x;
                  _auto();
                })),
          ]),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            for (final f in widget.fl) Padding(padding: const EdgeInsets.only(bottom: 12), child: _field(f)),
            Row(children: [
              if (widget.canDelete)
                TextButton.icon(
                    onPressed: () => Navigator.pop(context, <String, String>{'_del': '1'}),
                    icon: const Icon(Icons.delete_outline, color: red),
                    label: const Text('Sil', style: TextStyle(color: red))),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
              const SizedBox(width: 8),
              FilledButton(onPressed: _save, child: const Text('Kaydet')),
            ]),
          ]),
        ),
      );
}

Future<void> editRec(BuildContext c, List<R> list, String title, List<Fld> fl, {R? rec, R? defaults}) async {
  final res = await showForm(c, rec == null ? 'Yeni $title' : '$title düzenle', fl, rec ?? defaults ?? {}, canDelete: rec != null);
  if (res == null) return;
  if (res['_del'] == '1') {
    final idx = rec == null ? -1 : list.indexOf(rec);
    final msgr = ScaffoldMessenger.of(c);
    final silinen = rec;
    list.remove(rec);
    msgr
        .showSnackBar(SnackBar(
            content: const Text('Kayıt silindi'),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
                label: 'GERİ AL',
                onPressed: () {
                  if (silinen != null) {
                    list.insert(idx < 0 || idx > list.length ? list.length : idx, silinen);
                    S.commit();
                  }
                })))
        .closed
        .then((reason) {
      if (reason != SnackBarClosedReason.action && silinen != null) S.dropFotos(silinen['id'] ?? '');
    });
  } else if (rec == null) {
    final n = <String, String>{'id': S.id(), ...(defaults ?? {}), ...res};
    list.add(n);
    S.ensure(n);
  } else {
    rec.addAll(res);
    S.ensure(rec);
  }
  S.commit();
}

List<Fld> isFl() => [
      Fld('musteri', 'Müşteri / Adı Soyadı', 'p', S.musteriler, true),
      const Fld('tarih', 'Tarih', 'd'),
      Fld('makina', 'Makina', 'p', S.makinalar, true),
      Fld('operator', 'Operatör (ops.)', 'p', opNames(), true),
      const Fld('miktar', 'Saat (örn. 02:30) veya sefer sayısı'),
      const Fld('ucret', 'Birim ücret (₺)', 'n'),
      const Fld('alinan', 'Alınan (₺)', 'n'),
      const Fld('santiye', 'Şantiye / adres (ops.)'),
      const Fld('malzeme', 'Malzeme (ops.)', 'p', ['Toprak', 'Moloz', 'Kum', 'Mil', 'Taş', 'Hafriyat', 'Asfalt', 'Diğer']),
      const Fld('m3', 'Miktar m³ (ops.)', 'n'),
      const Fld('irsaliye', 'İrsaliye / fiş no (ops.)'),
      const Fld('konum', 'Konum (ops.) – düğmeyle al', 'g'),
      const Fld('aciklama', 'Açıklama', 'm'),
    ];
List<Fld> tahsilatFl() => const [Fld('tarih', 'Tarih', 'd'), Fld('alinan', 'Tahsil edilen tutar (₺)', 'n'), Fld('aciklama', 'Açıklama', 'm')];
List<Fld> giderFl() => [
      Fld('kalem', 'Gider kalemi / kişi', 'p', {...S.giderler.map((e) => e['kalem'] ?? '')}.where((e) => e.isNotEmpty).toList(), true),
      const Fld('tarih', 'Tarih', 'd'),
      const Fld('tutar', 'Tutar (₺)', 'n'),
      const Fld('mz', 'Bu gider mazot ödemesi mi?', 's', ['0=Hayır', '1=Evet (mazot borcumdan düşer)']),
      const Fld('aciklama', 'Açıklama', 'm'),
    ];
List<Fld> mazotFl() => [
      const Fld('tur', 'Tür', 's', turler),
      const Fld('tarih', 'Tarih', 'd'),
      Fld('makina', 'Makina (depodan çıkış / dışarıdan alımda)', 'p', S.makinalar, true),
      const Fld('litre', 'Litre', 'n'),
      const Fld('tutar', 'Toplam tutar ₺ (alım/girişte, ops.)', 'n'),
      const Fld('aciklama', 'Açıklama', 'm'),
    ];

// ============================ RAPOR (PDF / EXCEL) ============================
class Rep {
  final String title, sub;
  final List<String> head;
  final List<List<Object>> rows;
  final List<Object> foot;
  final Set<int> money;
  final List<Rep> extra;
  final String? photo;
  Rep(this.title, this.head, this.rows, {this.sub = '', this.foot = const [], this.money = const {}, this.extra = const [], this.photo});
}

String cellText(Object v, int col, Rep r, {bool pdf = false}) {
  if (v is num) return r.money.contains(col) ? tl(v.toDouble(), pdf ? 'TL' : '₺') : f2(v.toDouble());
  return v.toString();
}

String toText(Rep r) {
  final b = StringBuffer('${r.title}\n${r.sub}\n\n');
  for (final row in r.rows) {
    b.writeln([for (var i = 0; i < row.length; i++) cellText(row[i], i, r)].join(' | '));
  }
  if (r.foot.isNotEmpty) b.writeln('\n${[for (var i = 0; i < r.foot.length; i++) cellText(r.foot[i], i, r)].join(' | ')}');
  return b.toString();
}

// ---- PDF ----
Future<pw.ImageProvider?> _img(String? p) async {
  try {
    if (p == null || p.isEmpty) return null;
    final f = File(fp(p));
    if (!await f.exists()) return null;
    return pw.MemoryImage(await f.readAsBytes());
  } catch (_) {
    return null;
  }
}

List<pw.Widget> _pdfBlock(Rep r, {pw.ImageProvider? logo, bool dark = false, pw.ImageProvider? photo, String firm = ''}) {
  final n = r.head.length;
  final w = <int, pw.TableColumnWidth>{};
  for (var i = 0; i < n; i++) {
    var m = r.head[i].length;
    for (final row in r.rows) {
      final l = cellText(row[i], i, r, pdf: true).length;
      if (l > m) m = l;
    }
    w[i] = pw.FlexColumnWidth(m.clamp(4, 26).toDouble());
  }
  final right = [for (var i = 0; i < n; i++) r.rows.isNotEmpty && r.rows.first[i] is num];
  pw.Widget cell(String t, int i, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Align(
            alignment: right[i] ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
            child: pw.Text(t, style: pw.TextStyle(fontSize: 8.5, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal))),
      );
  return [
    pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(color: PdfColor.fromHex('#1F2937'), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6))),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(r.title, style: pw.TextStyle(color: PdfColors.white, fontSize: 15, fontWeight: pw.FontWeight.bold)),
            if (r.sub.isNotEmpty) pw.Text(r.sub, style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 9)),
            if (firm.isNotEmpty) pw.Text(firm, style: const pw.TextStyle(color: PdfColors.grey400, fontSize: 8)),
          ]),
        ),
        if (logo != null)
          pw.Container(
            padding: const pw.EdgeInsets.all(3),
            decoration: pw.BoxDecoration(color: dark ? PdfColors.black : PdfColors.white, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
            child: pw.Image(logo, height: 44),
          ),
      ]),
    ),
    pw.SizedBox(height: 8),
    if (photo != null) pw.Container(height: 130, alignment: pw.Alignment.center, margin: const pw.EdgeInsets.only(bottom: 8), child: pw.Image(photo, fit: pw.BoxFit.contain)),
    pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
      columnWidths: w,
      children: [
        pw.TableRow(repeat: true, decoration: pw.BoxDecoration(color: PdfColor.fromHex('#E5E7EB')), children: [for (var i = 0; i < n; i++) cell(r.head[i], i, bold: true)]),
        for (var k = 0; k < r.rows.length; k++)
          pw.TableRow(
              decoration: k.isOdd ? pw.BoxDecoration(color: PdfColor.fromHex('#F9FAFB')) : null,
              children: [for (var i = 0; i < n; i++) cell(cellText(r.rows[k][i], i, r, pdf: true), i)]),
        if (r.foot.isNotEmpty)
          pw.TableRow(
              decoration: pw.BoxDecoration(color: PdfColor.fromHex('#FDE9C4')),
              children: [for (var i = 0; i < n; i++) cell(cellText(r.foot[i], i, r, pdf: true), i, bold: true)]),
      ],
    ),
    pw.SizedBox(height: 16),
  ];
}

Future<List<int>> toPdf(Rep r) async {
  final reg = pw.Font.ttf(await rootBundle.load('assets/fonts/LiberationSans-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/LiberationSans-Bold.ttf'));
  final lp = await loadLogo();
  final logo = lp == null ? null : pw.MemoryImage(lp.orig);
  final wmImg = (lp != null && S.ayar['filigran'] != '0') ? pw.MemoryImage(lp.wm) : null;
  final photo = await _img(r.photo);
  final firm = [S.ayar['firma'] ?? '', S.ayar['tel'] ?? ''].where((e) => e.isNotEmpty).join(' · ');
  final doc = pw.Document();
  final wide = r.head.length > 6 || r.extra.any((e) => e.head.length > 6);
  doc.addPage(pw.MultiPage(
    pageTheme: pw.PageTheme(
      pageFormat: wide ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      theme: pw.ThemeData.withFont(base: reg, bold: bold),
      buildBackground: wmImg != null ? (ctx) => pw.FullPage(ignoreMargins: true, child: pw.Center(child: pw.Image(wmImg!, width: 380))) : null,
    ),
    footer: (ctx) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text(firm.isEmpty ? 'İş Takip · ${dshow(todayIso())}' : '$firm · ${dshow(todayIso())}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      pw.Text('Sayfa ${ctx.pageNumber}/${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
    ]),
    build: (ctx) => [..._pdfBlock(r, logo: logo, dark: lp?.dark ?? false, photo: photo, firm: firm), for (final e in r.extra) ..._pdfBlock(e, logo: logo, dark: lp?.dark ?? false)],
  ));
  return doc.save();
}

// ---- EXCEL (.xlsx, harici paket gerektirmez) ----
final _crcT = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
  }
  return c;
});
int _crc32(List<int> d) {
  var c = 0xFFFFFFFF;
  for (final b in d) {
    c = _crcT[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

Uint8List _zip(Map<String, List<int>> files) {
  final out = BytesBuilder(), cd = BytesBuilder();
  void w16(BytesBuilder b, int v) => b.add([v & 255, (v >> 8) & 255]);
  void w32(BytesBuilder b, int v) => b.add([v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255]);
  var off = 0;
  files.forEach((name, data) {
    final n = utf8.encode(name), c = _crc32(data);
    w32(out, 0x04034b50);
    w16(out, 20);
    w16(out, 0x0800);
    w16(out, 0);
    w16(out, 0);
    w16(out, 0x21);
    w32(out, c);
    w32(out, data.length);
    w32(out, data.length);
    w16(out, n.length);
    w16(out, 0);
    out.add(n);
    out.add(data);
    w32(cd, 0x02014b50);
    w16(cd, 20);
    w16(cd, 20);
    w16(cd, 0x0800);
    w16(cd, 0);
    w16(cd, 0);
    w16(cd, 0x21);
    w32(cd, c);
    w32(cd, data.length);
    w32(cd, data.length);
    w16(cd, n.length);
    w16(cd, 0);
    w16(cd, 0);
    w16(cd, 0);
    w16(cd, 0);
    w32(cd, 0);
    w32(cd, off);
    cd.add(n);
    off += 30 + n.length + data.length;
  });
  final cdb = cd.toBytes();
  out.add(cdb);
  w32(out, 0x06054b50);
  w16(out, 0);
  w16(out, 0);
  w16(out, files.length);
  w16(out, files.length);
  w32(out, cdb.length);
  w32(out, off);
  w16(out, 0);
  return out.toBytes();
}

String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
String _col(int i) {
  var s = '';
  var n = i + 1;
  while (n > 0) {
    final r = (n - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

const _xh = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
const _styles = '$_xh<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="1"><numFmt numFmtId="164" formatCode="#,##0.00"/></numFmts>'
    '<fonts count="4"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="14"/><name val="Calibri"/></font></fonts>'
    '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF1F2937"/><bgColor indexed="64"/></patternFill></fill></fills>'
    '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="5"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>'
    '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="164" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1" applyNumberFormat="1"/>'
    '<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs></styleSheet>';

String _sheetXml(Rep r) {
  final rows = <List<List<Object>>>[]; // her hücre: [değer, stil]
  rows.add([[r.title, 4]]);
  if (r.sub.isNotEmpty) rows.add([[r.sub, 0]]);
  rows.add([]);
  rows.add([for (final h in r.head) [h, 1]]);
  for (final row in r.rows) {
    rows.add([for (var i = 0; i < row.length; i++) [row[i], (row[i] is num && r.money.contains(i)) ? 2 : 0]]);
  }
  if (r.foot.isNotEmpty) rows.add([for (var i = 0; i < r.foot.length; i++) [r.foot[i], (r.foot[i] is num && r.money.contains(i)) ? 3 : 3]]);
  final widths = [for (var i = 0; i < r.head.length; i++) r.head[i].length];
  for (final row in r.rows) {
    for (var i = 0; i < row.length && i < widths.length; i++) {
      final l = row[i] is num ? 14 : row[i].toString().length;
      if (l > widths[i]) widths[i] = l;
    }
  }
  final b = StringBuffer('$_xh<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><cols>');
  for (var i = 0; i < widths.length; i++) {
    b.write('<col min="${i + 1}" max="${i + 1}" width="${(widths[i] + 3).clamp(8, 45)}" customWidth="1"/>');
  }
  b.write('</cols><sheetData>');
  for (var ri = 0; ri < rows.length; ri++) {
    b.write('<row r="${ri + 1}">');
    for (var ci = 0; ci < rows[ri].length; ci++) {
      final v = rows[ri][ci][0], s = rows[ri][ci][1];
      final ref = '${_col(ci)}${ri + 1}';
      if (v is num) {
        b.write('<c r="$ref" s="$s"><v>$v</v></c>');
      } else {
        b.write('<c r="$ref" s="$s" t="inlineStr"><is><t xml:space="preserve">${_esc(v.toString())}</t></is></c>');
      }
    }
    b.write('</row>');
  }
  b.write('</sheetData></worksheet>');
  return b.toString();
}

List<int> toXlsx(Rep r) {
  final all = [r, ...r.extra];
  final files = <String, List<int>>{};
  final ct = StringBuffer('$_xh<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>');
  final wb = StringBuffer('$_xh<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>');
  final rel = StringBuffer('$_xh<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
  for (var i = 0; i < all.length; i++) {
    final n = i + 1;
    var name = all[i].title.replaceAll(RegExp(r'[\\/?*\[\]:]'), ' ');
    if (name.length > 28) name = name.substring(0, 28);
    ct.write('<Override PartName="/xl/worksheets/sheet$n.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
    wb.write('<sheet name="${_esc(name)}${i == 0 ? '' : ' $n'}" sheetId="$n" r:id="rId$n"/>');
    rel.write('<Relationship Id="rId$n" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$n.xml"/>');
    files['xl/worksheets/sheet$n.xml'] = utf8.encode(_sheetXml(all[i]));
  }
  rel.write('<Relationship Id="rId${all.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>');
  ct.write('</Types>');
  wb.write('</sheets></workbook>');
  final ordered = <String, List<int>>{
    '[Content_Types].xml': utf8.encode(ct.toString()),
    '_rels/.rels': utf8.encode('$_xh<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'),
    'xl/workbook.xml': utf8.encode(wb.toString()),
    'xl/_rels/workbook.xml.rels': utf8.encode(rel.toString()),
    'xl/styles.xml': utf8.encode(_styles),
    ...files,
  };
  return _zip(ordered);
}

Future<String?> shareBytes(List<int> bytes, String name) async {
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes);
    try {
      await launchUrl(Uri.file(f.path));
    } catch (_) {}
    return f.path;
  }
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/$name');
  await f.writeAsBytes(bytes);
  await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], subject: name));
  return null;
}

Future<void> exportSheet(BuildContext c, String title, Rep Function(int, String?) build,
        {List<String> scopes = const [], String? selLabel, List<String> Function()? selOptions, bool musteri = false}) =>
    showModalBottomSheet(context: c, showDragHandle: true, isScrollControlled: true, builder: (_) => _ExportSheet(title, build, scopes, selLabel, selOptions, musteri));

class _ExportSheet extends StatefulWidget {
  final String title;
  final Rep Function(int, String?) build;
  final List<String> scopes;
  final String? selLabel;
  final List<String> Function()? selOptions;
  final bool musteri;
  const _ExportSheet(this.title, this.build, this.scopes, this.selLabel, this.selOptions, this.musteri);
  @override
  State<_ExportSheet> createState() => _ExportState();
}

class _ExportState extends State<_ExportSheet> {
  int scope = 0;
  String? sel;
  bool busy = false;

  Future<void> _go(String t) async {
    setState(() => busy = true);
    try {
      final r = widget.build(scope, sel);
      final slug = '${norm(r.title).replaceAll(RegExp(r'[^a-z0-9]+'), '_')}_${todayIso()}';
      if (t == 'pdf') {
        final pth = await shareBytes(await toPdf(r), '$slug.pdf');
        if (pth != null && mounted) msg(context, 'İndirilenler klasörüne kaydedildi: $pth');
      } else if (t == 'xlsx') {
        final pth = await shareBytes(toXlsx(r), '$slug.xlsx');
        if (pth != null && mounted) msg(context, 'İndirilenler klasörüne kaydedildi: $pth');
      } else if (t == 'wa') {
        final single = widget.musteri && sel != null && !sel!.startsWith('Kategori: ');
        final txt = single ? waEkstre(sel!) : toWa(r);
        final ph = widget.musteri && sel != null ? S.telefon[norm(sel!)] : null;
        if (txt.length > 3300) {
          await Clipboard.setData(ClipboardData(text: txt));
          if (mounted) msg(context, 'Rapor uzun olduğu için panoya kopyalandı. WhatsApp\'ta yapıştırın.');
          if (mounted) await whatsapp(context, ph, '');
        } else {
          await whatsapp(context, ph, txt);
        }
      } else {
        await Clipboard.setData(ClipboardData(text: toText(r)));
        if (mounted) msg(context, 'Rapor metni panoya kopyalandı.');
      }
    } catch (e) {
      if (mounted) msg(context, 'Hata: $e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            if (widget.selLabel != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Material(
                  color: sel == null ? cardC(context) : amber.withAlpha(40),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: lineC(context))),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () async {
                      final v = await pickKey(context, widget.selLabel!, widget.selOptions!(), sel);
                      if (v != null) setState(() => sel = v.isEmpty ? null : v);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      child: Row(children: [
                        Icon(Icons.filter_alt_outlined, color: sel == null ? grey : inkNavy),
                        const SizedBox(width: 8),
                        Expanded(child: Text(sel ?? '${widget.selLabel}: Tümü', style: TextStyle(fontWeight: FontWeight.w600, color: sel == null ? grey : inkNavy))),
                        if (sel != null) InkWell(onTap: () => setState(() => sel = null), child: const Icon(Icons.close, size: 20)) else const Icon(Icons.arrow_drop_down, color: grey),
                      ]),
                    ),
                  ),
                ),
              ),
            if (widget.scopes.length > 1 && sel == null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(spacing: 8, children: [
                  for (var i = 0; i < widget.scopes.length; i++) ChoiceChip(label: Text(widget.scopes[i]), selected: scope == i, onSelected: (_) => setState(() => scope = i)),
                ]),
              ),
            const SizedBox(height: 6),
            if (busy) const LinearProgressIndicator(),
            ListTile(leading: const Icon(Icons.picture_as_pdf, color: red), title: const Text('PDF olarak paylaş / kaydet'), onTap: busy ? null : () => _go('pdf')),
            ListTile(leading: const Icon(Icons.table_chart, color: green), title: const Text('Excel (.xlsx) olarak paylaş / kaydet'), onTap: busy ? null : () => _go('xlsx')),
            ListTile(leading: const Icon(Icons.chat, color: Color(0xFF25D366)), title: const Text('WhatsApp\'a metin olarak gönder'), onTap: busy ? null : () => _go('wa')),
            ListTile(leading: const Icon(Icons.copy), title: const Text('Metin olarak kopyala'), onTap: busy ? null : () => _go('txt')),
          ]),
        ),
      );
}

// ---- Rapor içerikleri ----
Rep repMusteri(int scope, [String? kat]) {
  final kk = kat == 'Kategorisiz' ? '' : kat;
  final l = S.cust.values.where((s) => s.durum != 'yok' && (scope == 0 || s.kalan > 0.5) && (kat == null || S.mCat(s.name) == kk)).toList()..sort((a, b) => b.kalan.compareTo(a.kalan));
  final names = {...l.map((s) => norm(s.name))};
  final det = S.isler.where((r) => names.contains(norm(r['musteri'] ?? ''))).toList()
    ..sort((a, b) {
      final c = norm(a['musteri'] ?? '').compareTo(norm(b['musteri'] ?? ''));
      return c != 0 ? c : cmpDate(a, b);
    });
  return Rep(
    kat != null ? 'Müşteri - $kat' : (scope == 0 ? 'Müşteri Raporu' : 'Borçlu Müşteriler'),
    ['Müşteri', 'Kategori', 'İş', 'Borç', 'Alınan', 'Kalan', 'Durum', 'En eski ödenmemiş'],
    [for (final s in l) [s.name, S.mCat(s.name), s.n, s.borc, s.alinan, s.kalan, durumAd[s.durum]!, (s.oldest != null && s.kalan > 0.5) ? dshow(s.oldest) : '']],
    sub: '${l.length} müşteri · Tarih: ${dshow(todayIso())}',
    foot: ['TOPLAM', '', l.fold<int>(0, (a, s) => a + s.n), l.fold<double>(0.0, (a, s) => a + s.borc), l.fold<double>(0.0, (a, s) => a + s.alinan), l.fold<double>(0.0, (a, s) => a + s.kalan), '', ''],
    money: {3, 4, 5},
    extra: [
      Rep('Is detayi', ['Müşteri', 'Tarih', 'Makina', 'Miktar', 'Birim ücret', 'Borç', 'Alınan'],
          [for (final r in det) [r['musteri'] ?? '', dshow(r['tarih']), r['makina'] ?? '', r['miktar'] ?? '', toD(r['ucret']), borc(r), toD(r['alinan'])]],
          sub: 'Tüm iş ve tahsilat kayıtları', money: {4, 5, 6})
    ],
  );
}

Rep repGider(int m, [String? sel]) {
  var l = S.byMonth(S.giderler, m);
  String? cat, kalem;
  if (sel != null) {
    if (sel.startsWith('Kategori: ')) {
      cat = sel.substring(10);
    } else {
      kalem = sel;
    }
  }
  if (kalem != null) l = l.where((r) => norm(r['kalem'] ?? '') == norm(kalem!)).toList();
  if (cat != null) l = l.where((r) => S.gCat(r['kalem'] ?? '') == (cat == 'Kategorisiz' ? '' : cat)).toList();
  final tot = sum(l, (r) => toD(r['tutar']));
  if (kalem != null) {
    final d = [...l]..sort(cmpDate);
    return Rep('Gider - $kalem', ['Tarih', 'Açıklama', 'Tutar'], [for (final r in d) [dshow(r['tarih']), r['aciklama'] ?? '', toD(r['tutar'])]],
        sub: 'Dönem: ${aylar[m]} · ${l.length} kayıt', foot: ['TOPLAM', '', tot], money: {2});
  }
  final g = groupBy(l, (r) => r['kalem'] ?? '-')..sort((a, b) => sum(b.l, (r) => toD(r['tutar'])).compareTo(sum(a.l, (r) => toD(r['tutar']))));
  final det = [...l]..sort((a, b) {
      final c = norm(a['kalem'] ?? '').compareTo(norm(b['kalem'] ?? ''));
      return c != 0 ? c : cmpDate(a, b);
    });
  final ks = <String, double>{}, kc = <String, int>{};
  for (final r in l) {
    final c0 = S.gCat(r['kalem'] ?? '');
    final c = c0.isEmpty ? 'Kategorisiz' : c0;
    ks[c] = (ks[c] ?? 0) + toD(r['tutar']);
    kc[c] = (kc[c] ?? 0) + 1;
  }
  final kl = ks.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return Rep(
    cat != null ? 'Gider - Kategori $cat' : 'Gider Raporu',
    ['Gider kalemi / kişi', 'Kategori', 'Kayıt', 'Toplam'],
    [for (final x in g) [x.key, S.gCat(x.key), x.l.length, sum(x.l, (r) => toD(r['tutar']))]],
    sub: 'Dönem: ${aylar[m]} · ${l.length} kayıt',
    foot: ['TOPLAM', '', l.length, tot],
    money: {3},
    extra: [
      if (cat == null && S.gKatList.isNotEmpty) Rep('Kategori ozeti', ['Kategori', 'Kayıt', 'Toplam'], [for (final e in kl) [e.key, kc[e.key]!, e.value]], sub: 'Giderlerin kategorilere göre dağılımı', money: {2}),
      Rep('Gider detayi', ['Tarih', 'Kalem', 'Tutar', 'Açıklama'], [for (final r in det) [dshow(r['tarih']), r['kalem'] ?? '', toD(r['tutar']), r['aciklama'] ?? '']], sub: 'Tüm gider kayıtları', money: {2}),
    ],
  );
}

Rep repMakina(int m, [String? name]) {
  if (name != null) {
    final k = norm(name);
    final st = S.makinaStat(m).firstWhere((s) => norm(s.name) == k, orElse: () => MStat(name));
    final jobs = S.byMonth(S.isler, m).where((r) => norm(r['makina'] ?? '') == k).toList()..sort(cmpDate);
    final fuel = S.byMonth(S.mazot, m).where((r) => r['tur'] != 'giren' && norm(r['makina'] ?? '') == k).toList()..sort(cmpDate);
    return Rep(
      'Makina - $name',
      ['Tarih', 'Müşteri', 'Miktar', 'Birim ücret', 'Borç'],
      [for (final r in jobs) [dshow(r['tarih']), r['musteri'] ?? '', r['miktar'] ?? '', toD(r['ucret']), borc(r)]],
      sub: 'Dönem: ${aylar[m]} · Çalışma: ${st.active ? st.calisma : '-'} · Yakıt: ${f2(st.litre)} L · Gelir: ${tl(st.gelir, 'TL')} · Kâr: ${tl(st.kar, 'TL')}',
      foot: ['TOPLAM', '', '', '', st.gelir],
      money: {3, 4},
      photo: S.foto[k],
      extra: [
        Rep('Yakit', ['Tarih', 'Litre'], [for (final r in fuel) [dshow(r['tarih']), toD(r['litre'])]], sub: 'Yakıt çıkışları', foot: ['TOPLAM', sum(fuel, (r) => toD(r['litre']))])
      ],
    );
  }
  final l = S.makinaStat(m).where((s) => s.active).toList();
  return Rep(
    'Makina Raporu',
    ['Makina', 'Çalışma', 'Mazot L', 'L/birim', 'Gelir', 'Mazot ₺', 'Kâr'],
    [for (final s in l) [s.name, s.calisma, s.litre, s.lPerUnit, s.gelir, s.mazotTl, s.kar]],
    sub: 'Dönem: ${aylar[m]}',
    foot: ['TOPLAM', '', l.fold<double>(0.0, (a, s) => a + s.litre), '', l.fold<double>(0.0, (a, s) => a + s.gelir), l.fold<double>(0.0, (a, s) => a + s.mazotTl), l.fold<double>(0.0, (a, s) => a + s.kar)],
    money: {4, 5, 6},
  );
}

Rep repEkstre(String name) {
  final l = S.isler.where((r) => norm(r['musteri'] ?? '') == norm(name)).toList()..sort(cmpDate);
  var bak = 0.0;
  final rows = <List<Object>>[];
  for (final r in l) {
    bak += borc(r) - toD(r['alinan']);
    rows.add([dshow(r['tarih']), r['makina'] ?? '', r['miktar'] ?? '', toD(r['ucret']), borc(r), toD(r['alinan']), bak]);
  }
  final s = S.cust[norm(name)];
  return Rep('Ekstre - $name', ['Tarih', 'Makina', 'Miktar', 'Birim ücret', 'Borç', 'Alınan', 'Bakiye'], rows,
      sub: 'Durum: ${durumAd[s?.durum ?? 'yok']} · Kalan: ${tl(s?.kalan ?? 0, 'TL')} · ${dshow(todayIso())}',
      foot: ['TOPLAM', '', '', '', s?.borc ?? 0, s?.alinan ?? 0, s?.kalan ?? 0],
      money: {3, 4, 5, 6});
}

// ============================ GRUPLAMA ALTYAPISI ============================
class Grp {
  final String key;
  final List<R> l;
  Grp(this.key, this.l);
  String get last => l.fold('', (a, r) => (r['tarih'] ?? '').compareTo(a) > 0 ? (r['tarih'] ?? '') : a);
}

List<Grp> groupBy(List<R> l, String Function(R) kf) {
  final m = <String, List<R>>{}, names = <String, String>{};
  for (final r in l) {
    final k = kf(r).trim().isEmpty ? 'Belirtilmemiş' : kf(r).trim();
    final n = norm(k);
    names.putIfAbsent(n, () => k);
    (m[n] ??= []).add(r);
  }
  return [for (final e in m.entries) Grp(names[e.key]!, e.value)];
}

class SortOpt {
  final String label;
  final int Function(Grp, Grp) cmp;
  SortOpt(this.label, this.cmp);
}

class GCfg {
  final String title, selLabel;
  final List<R> Function() items;
  final String Function(R) keyOf;
  final List<String> Function() allKeys;
  final List<SortOpt> sorts;
  final Widget Function(BuildContext, Grp) card;
  final Widget Function(BuildContext, R) rec;
  final Widget Function(List<R>) summary;
  final String Function(List<R>) monthSum;
  final void Function(BuildContext, String?) onAdd;
  final bool month;
  final List<String> Function(R)? keysOf;
  final List<String> Function()? cats;
  final String Function(String)? catOf;
  final List<Widget> Function(BuildContext)? actions;
  final List<Widget> Function(BuildContext, String)? detailActions;
  List<String> ks(R r) => keysOf?.call(r) ?? [keyOf(r)];
  GCfg({this.month = true, this.keysOf, this.cats, this.catOf, this.actions, this.detailActions, required this.title, required this.selLabel, required this.items, required this.keyOf, required this.allKeys, required this.sorts, required this.card, required this.rec, required this.summary, required this.monthSum, required this.onAdd});
}

List<Widget> detailRows(BuildContext c, GCfg cfg, List<R> l) {
  final s = [...l]..sort((a, b) => cmpDate(b, a));
  final out = <Widget>[];
  String? cur;
  for (final r in s) {
    final t = r['tarih'] ?? '';
    final m = t.length >= 7 ? t.substring(0, 7) : '';
    if (m != cur) {
      cur = m;
      final grp = s.where((x) => (x['tarih'] ?? '').startsWith(m)).toList();
      final mi = int.tryParse(m.length >= 7 ? m.substring(5, 7) : '') ?? 0;
      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
        child: Row(children: [
          Text('${aylar[mi]} ${m.length >= 4 ? m.substring(0, 4) : ''}'.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: grey, letterSpacing: .5)),
          const Spacer(),
          Text('${grp.length} kayıt · ${cfg.monthSum(grp)}', style: const TextStyle(fontSize: 12, color: grey)),
        ]),
      ));
    }
    out.add(cfg.rec(c, r));
  }
  return out;
}

List<Grp> groupByCfg(List<R> l, GCfg cfg) {
  final m = <String, List<R>>{}, names = <String, String>{};
  for (final r in l) {
    for (final kk in cfg.ks(r)) {
      final k = kk.trim().isEmpty ? 'Belirtilmemiş' : kk.trim();
      final n = norm(k);
      names.putIfAbsent(n, () => k);
      (m[n] ??= []).add(r);
    }
  }
  return [for (final e in m.entries) Grp(names[e.key]!, e.value)];
}

class GroupView extends StatefulWidget {
  final GCfg cfg;
  const GroupView(this.cfg, {super.key});
  @override
  State<GroupView> createState() => _GVState();
}

class _GVState extends State<GroupView> {
  String q = '';
  int sort = 0;
  String? sel, cat;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: Listenable.merge([S, ayF]),
      builder: (c, _) {
        final cfg = widget.cfg;
        final all = cfg.items();
        var groups = groupByCfg(all, cfg);
        final k = norm(q);
        if (k.isNotEmpty) {
          groups = groups.where((g) => norm(g.key).contains(k) || g.l.any((r) => r.values.any((v) => norm(v).contains(k)) || norm(dshow(r['tarih'])).contains(k))).toList();
        }
        if (cfg.cats != null && cat != null) {
          groups = groups.where((g) => (cfg.catOf!(g.key).isEmpty ? '__none' : cfg.catOf!(g.key)) == cat).toList();
        }
        groups.sort(cfg.sorts[sort].cmp);
        Grp? sg;
        if (sel != null) {
          for (final g in groupByCfg(all, cfg)) {
            if (norm(g.key) == norm(sel!)) sg = g;
          }
        }
        return Scaffold(
          appBar: AppBar(title: Text(cfg.title), actions: [...?cfg.actions?.call(c), if (cfg.month) const AyDrop()]),
          body: Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 6), child: searchBox((v) => setState(() => q = v), 'Ara…')),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Material(
                color: sel == null ? cardC(context) : amber.withAlpha(40),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: lineC(context))),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () async {
                    final v = await pickKey(c, cfg.selLabel, cfg.allKeys(), sel);
                    if (v != null) setState(() => sel = v.isEmpty ? null : v);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(children: [
                      Icon(Icons.filter_alt_outlined, color: sel == null ? grey : inkNavy),
                      const SizedBox(width: 8),
                      Expanded(child: Text(sel ?? '${cfg.selLabel}: Tümü', style: TextStyle(fontWeight: FontWeight.w600, color: sel == null ? grey : inkNavy), overflow: TextOverflow.ellipsis)),
                      if (sel != null) InkWell(onTap: () => setState(() => sel = null), child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.close, size: 20)))
                      else const Icon(Icons.arrow_drop_down, color: grey),
                    ]),
                  ),
                ),
              ),
            ),
            if (sel == null && cfg.sorts.length > 1)
              SizedBox(
                height: 40,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                  for (var i = 0; i < cfg.sorts.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(label: Text(cfg.sorts[i].label), selected: sort == i, onSelected: (_) => setState(() => sort = i)),
                    ),
                ]),
              ),
            if (sel == null && cfg.cats != null && cfg.cats!().isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                  Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: const Text('Tüm kategoriler'), selected: cat == null, onSelected: (_) => setState(() => cat = null))),
                  for (final kt in cfg.cats!())
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(avatar: CircleAvatar(radius: 5, backgroundColor: katColor(kt)), label: Text(kt), selected: cat == kt, onSelected: (_) => setState(() => cat = kt)),
                    ),
                  Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: const Text('Kategorisiz'), selected: cat == '__none', onSelected: (_) => setState(() => cat = '__none'))),
                ]),
              ),
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(12, 6, 12, 90), children: [
                if (sel == null) ...[
                  cfg.summary(all),
                  const SizedBox(height: 10),
                  if (groups.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('Kayıt bulunamadı'))),
                  for (final g in groups) cfg.card(c, g),
                ] else ...[
                  if (sg == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('Bu dönemde kayıt yok'))),
                  if (sg != null) ...[cfg.summary(sg.l), ...detailRows(c, cfg, sg.l)],
                ],
              ]),
            ),
          ]),
          floatingActionButton: FloatingActionButton(onPressed: () => cfg.onAdd(c, sel), child: const Icon(Icons.add)),
        );
      });
}

class GroupDetailPage extends StatelessWidget {
  final GCfg cfg;
  final String keyName;
  const GroupDetailPage(this.cfg, this.keyName, {super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: Listenable.merge([S, ayF]),
      builder: (c, _) {
        final l = cfg.items().where((r) => cfg.ks(r).any((x) => norm(x) == norm(keyName))).toList();
        return Scaffold(
          appBar: AppBar(title: Text(keyName, overflow: TextOverflow.ellipsis), actions: [...?cfg.detailActions?.call(c, keyName), if (cfg.month) const AyDrop()]),
          body: ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 90), children: [
            cfg.summary(l),
            const SizedBox(height: 4),
            if (l.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('Bu dönemde kayıt yok'))),
            ...detailRows(c, cfg, l),
          ]),
          floatingActionButton: FloatingActionButton(onPressed: () => cfg.onAdd(c, keyName), child: const Icon(Icons.add)),
        );
      });
}

// ============================ İŞLER ============================
Widget jobRec(BuildContext c, R r) {
  final b = borc(r), a = toD(r['alinan']), k = b - a;
  final tah = b == 0 && a > 0;
  final pc = S.isFoto.where((f) => f['is'] == r['id']).length;
  return Box(
    pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    bottom: 6,
    onTap: () => tah ? tahsilatMenu(c, r) : push(c, IsDetayPage(r['id'] ?? '')),
    child: Row(children: [
      Icon(tah ? Icons.south_west : Icons.construction, color: tah ? green : inkNavy, size: 20),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text(tah ? 'Tahsilat' : '${r['makina'] ?? ''} · ${r['miktar'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600))),
            if (pc > 0) ...[const SizedBox(width: 8), const Icon(Icons.photo_camera, size: 13, color: grey), Text(' $pc', style: const TextStyle(fontSize: 12, color: grey))],
          ]),
          Text('${dshow(r['tarih'])}${(r['musteri'] ?? '').isEmpty ? '' : ' · ${r['musteri']}'}${(r['operator'] ?? '').isEmpty ? '' : ' · 👷 ${r['operator']}'}${(r['santiye'] ?? '').isEmpty ? '' : ' · 📍 ${r['santiye']}'}${(r['aciklama'] ?? '').isEmpty || tah ? '' : '\n${r['aciklama']}'}', style: const TextStyle(fontSize: 12, color: grey)),
        ]),
      ),
      if (tah) Text('+${tl(a)}', style: const TextStyle(fontWeight: FontWeight.w700, color: green)) else two(tl(b), k.abs() < 0.5 ? 'ödendi' : 'kalan ${tl(k)}', bc: k > 0.5 ? red : green),
    ]),
  );
}

Widget _sumRow(List<Widget> w) => Box(child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: w));

class IslerTab extends StatelessWidget {
  IslerTab({super.key});
  final cfg = GCfg(
    title: 'İşler',
    selLabel: 'Müşteri seç',
    items: () => S.byMonth(S.isler, ayF.value).toList(),
    keyOf: (r) => r['musteri'] ?? '',
    allKeys: () => [...S.musteriler]..sort((a, b) => norm(a).compareTo(norm(b))),
    sorts: [
      SortOpt('En çok borç', (a, b) => (S.cust[norm(b.key)]?.kalan ?? 0).compareTo(S.cust[norm(a.key)]?.kalan ?? 0)),
      SortOpt('En eski ödenmemiş', (a, b) {
        final x = (S.cust[norm(a.key)]?.kalan ?? 0) > 0.5 ? S.cust[norm(a.key)]?.oldest : null;
        final y = (S.cust[norm(b.key)]?.kalan ?? 0) > 0.5 ? S.cust[norm(b.key)]?.oldest : null;
        if (x == null && y == null) return 0;
        if (x == null) return 1;
        if (y == null) return -1;
        return x.compareTo(y);
      }),
      SortOpt('Son işlem', (a, b) => b.last.compareTo(a.last)),
      SortOpt('A–Z', (a, b) => norm(a.key).compareTo(norm(b.key))),
    ],
    card: (c, g) => musteriCard(c, g.key, sub: '${g.l.length} kayıt · dönem borcu ${tl(sum(g.l, borc))}'),
    rec: jobRec,
    summary: (l) => _sumRow([
      two(tl(sum(l, borc)), 'Borç'),
      two(tl(sum(l, (r) => toD(r['alinan']))), 'Alınan'),
      two(tl(sum(l, borc) - sum(l, (r) => toD(r['alinan']))), 'Kalan', ac: red),
    ]),
    monthSum: (l) => 'borç ${tl(sum(l, borc))}',
    onAdd: (c, k) => editRec(c, S.isler, 'iş', isFl(), defaults: k == null ? null : {'musteri': k}),
  );
  @override
  Widget build(BuildContext context) => GroupView(cfg);
}

Widget musteriCard(BuildContext c, String name, {String? sub}) {
  final s = S.cust[norm(name)] ?? CStat(name);
  final rk = S.rank(name);
  final d = s.durum;
  return Box(
    onTap: () => push(c, MusteriDetay(name)),
    color: rk >= 0 ? goldBg : null,
    border: rk >= 0 ? gold : null,
    child: Row(children: [
      Avatar(name),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
            if (rk >= 0) const SizedBox(width: 6),
            if (rk >= 0) Pill('★ ${rk + 1}', gold),
            if (S.mCat(name).isNotEmpty) ...[const SizedBox(width: 6), Pill(S.mCat(name), katColor(S.mCat(name)))],
          ]),
          const SizedBox(height: 2),
          Text(sub ?? 'Borç ${tl(s.borc)} · Alınan ${tl(s.alinan)}', style: const TextStyle(fontSize: 12, color: grey)),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: [Pill(durumAd[d]!, durumRenk[d]!), agePill(s)]),
        ]),
      ),
      const SizedBox(width: 8),
      two(tl(s.kalan), 'kalan', ac: s.kalan > 0.5 ? red : green),
    ]),
  );
}

// ============================ GİDER ============================
class GiderTab extends StatelessWidget {
  GiderTab({super.key});
  late final GCfg cfg = GCfg(
    title: 'Gider',
    selLabel: 'Kalem / kişi seç',
    items: () => S.byMonth(S.giderler, ayF.value).toList(),
    keyOf: (r) => r['kalem'] ?? '',
    allKeys: () => ({...S.giderler.map((e) => (e['kalem'] ?? '').trim())}.where((e) => e.isNotEmpty).toList())..sort((a, b) => norm(a).compareTo(norm(b))),
    cats: () => S.gKatList,
    catOf: (k) => S.gCat(k),
    actions: (c) => [IconButton(icon: const Icon(Icons.category_outlined), tooltip: 'Kategorileri yönet', onPressed: () => push(c, const KatPage(true)))],
    detailActions: (c, k) => [
      IconButton(
          icon: const Icon(Icons.label_outline),
          tooltip: 'Kategori ata',
          onPressed: () async {
            final v = await pickCat(c, true, S.gCat(k));
            if (v == null) return;
            if (v.isEmpty) {
              S.gKat.remove(norm(k));
            } else {
              S.gKat[norm(k)] = v;
            }
            S.commit();
          })
    ],
    sorts: [
      SortOpt('En yüksek tutar', (a, b) => sum(b.l, (r) => toD(r['tutar'])).compareTo(sum(a.l, (r) => toD(r['tutar'])))),
      SortOpt('En çok kayıt', (a, b) => b.l.length.compareTo(a.l.length)),
      SortOpt('Son kayıt', (a, b) => b.last.compareTo(a.last)),
      SortOpt('A–Z', (a, b) => norm(a.key).compareTo(norm(b.key))),
    ],
    card: (c, g) {
      final ct = S.gCat(g.key);
      return Box(
        onTap: () => push(c, GroupDetailPage(cfg, g.key)),
        child: Row(children: [
          Avatar(g.key),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(g.key, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                if (ct.isNotEmpty) ...[const SizedBox(width: 6), Pill(ct, katColor(ct))],
              ]),
              Text('${g.l.length} kayıt · son: ${dshow(g.last)}', style: const TextStyle(fontSize: 12, color: grey)),
            ]),
          ),
          Text(tl(sum(g.l, (r) => toD(r['tutar']))), style: const TextStyle(fontWeight: FontWeight.w700, color: red)),
          const Icon(Icons.chevron_right, color: grey),
        ]),
      );
    },
    rec: (c, r) => Box(
      pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      bottom: 6,
      onTap: () => editRec(c, S.giderler, 'gider', giderFl(), rec: r),
      child: Row(children: [
        const Icon(Icons.receipt_long, color: red, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Text(dshow(r['tarih']), style: const TextStyle(fontWeight: FontWeight.w600)), if (mzOde(r)) ...[const SizedBox(width: 8), const Pill('Mazot ödemesi', orange)]]),
            if ((r['aciklama'] ?? '').isNotEmpty) Text(r['aciklama']!, style: const TextStyle(fontSize: 12, color: grey)),
          ]),
        ),
        Text(tl(toD(r['tutar'])), style: const TextStyle(fontWeight: FontWeight.w700, color: red)),
      ]),
    ),
    summary: (l) => _sumRow([two(tl(sum(l, (r) => toD(r['tutar']))), 'Toplam gider', ac: red), two('${l.length}', 'kayıt'), two('${groupBy(l, (r) => r['kalem'] ?? '').length}', 'kalem')]),
    monthSum: (l) => tl(sum(l, (r) => toD(r['tutar']))),
    onAdd: (c, k) => editRec(c, S.giderler, 'gider', giderFl(), defaults: k == null ? null : {'kalem': k}),
  );
  @override
  Widget build(BuildContext context) => GroupView(cfg);
}

// ============================ MAZOT ============================
String _mn(R r) => (r['makina'] ?? '').trim().isEmpty ? 'Makina belirtilmemiş' : r['makina']!.trim();
String mKey(R r) => r['tur'] == 'giren' ? 'Depo girişleri' : (r['tur'] == 'alim' ? 'Dışarıdan alımlar' : _mn(r));
// Dışarıdan alım hem "Dışarıdan alımlar" grubunda hem (makina yazıldıysa) o makinanın grubunda görünür
List<String> mKeys(R r) => r['tur'] == 'giren'
    ? ['Depo girişleri']
    : (r['tur'] == 'alim' ? ['Dışarıdan alımlar', if ((r['makina'] ?? '').trim().isNotEmpty) r['makina']!.trim()] : [_mn(r)]);

class MazotTab extends StatelessWidget {
  MazotTab({super.key});
  late final GCfg cfg = GCfg(
    title: 'Mazot',
    selLabel: 'Makina seç',
    items: () => S.byMonth(S.mazot, ayF.value).toList(),
    keyOf: mKey,
    keysOf: mKeys,
    allKeys: () => ['Depo girişleri', 'Dışarıdan alımlar', ...S.makinalar],
    sorts: [
      SortOpt('En çok litre', (a, b) => sum(b.l, (r) => toD(r['litre'])).compareTo(sum(a.l, (r) => toD(r['litre'])))),
      SortOpt('Son kayıt', (a, b) => b.last.compareTo(a.last)),
      SortOpt('A–Z', (a, b) => norm(a.key).compareTo(norm(b.key))),
    ],
    card: (c, g) {
      final depoG = g.key == 'Depo girişleri', disG = g.key == 'Dışarıdan alımlar';
      final lit = sum(g.l, (r) => toD(r['litre']));
      double tut, fill;
      Color col;
      String sub;
      if (depoG) {
        tut = sum(g.l, (r) => toD(r['tutar']));
        fill = lit == 0 ? 0.0 : (S.depo / lit);
        col = blue;
        sub = '${g.l.length} kayıt · depoda ${f2(S.depo)} L';
      } else if (disG) {
        tut = sum(g.l, (r) => toD(r['tutar']));
        fill = 0.6;
        col = const Color(0xFF00897B);
        sub = '${g.l.length} alım';
      } else {
        final dep = sum(g.l.where((r) => r['tur'] == 'cikan'), (r) => toD(r['litre']));
        final dis = sum(g.l.where((r) => r['tur'] == 'alim'), (r) => toD(r['litre']));
        tut = sum(g.l, (r) => (r['tur'] == 'alim' && toD(r['tutar']) > 0) ? toD(r['tutar']) : toD(r['litre']) * S.avgPrice);
        final mx = S.makinaStat(0).fold<double>(0.0, (a, s) => s.litre > a ? s.litre : a);
        fill = mx == 0 ? 0.0 : lit / mx;
        col = mColor(g.key);
        sub = '${g.l.length} kayıt · depodan ${f2(dep)} L · dışarıdan ${f2(dis)} L';
      }
      return Box(
        onTap: () => push(c, GroupDetailPage(cfg, g.key)),
        child: Row(children: [
          TankIcon(col, fill),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(g.key, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              Text(sub, style: const TextStyle(fontSize: 12, color: grey)),
            ]),
          ),
          two('${f2(lit)} L', tut > 0 ? ((depoG || disG) ? tl(tut) : '≈ ${tl(tut)}') : ''),
          const Icon(Icons.chevron_right, color: grey),
        ]),
      );
    },
    rec: (c, r) {
      final t = r['tur'], mk = (r['makina'] ?? '').trim();
      final ic = t == 'giren' ? Icons.south_west : (t == 'alim' ? Icons.shopping_cart_outlined : Icons.north_east);
      final cl = t == 'giren' ? green : (t == 'alim' ? const Color(0xFF00897B) : orange);
      final lab = t == 'giren' ? 'Depoya giriş' : (t == 'alim' ? 'Dışarıdan alım${mk.isEmpty ? '' : ' · $mk'}' : 'Depodan${mk.isEmpty ? '' : ' · $mk'}');
      return Box(
        pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        bottom: 6,
        onTap: () => editRec(c, S.mazot, 'mazot kaydı', mazotFl(), rec: r),
        child: Row(children: [
          Icon(ic, color: cl, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(dshow(r['tarih']), style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(lab, style: const TextStyle(fontSize: 12, color: grey)),
            ]),
          ),
          two('${r['litre'] ?? '0'} L', toD(r['tutar']) > 0 ? tl(toD(r['tutar'])) : ''),
        ]),
      );
    },
    summary: (l) => Column(children: [
      _sumRow([
        two('${f2(S.depo)} L', 'Depoda (toplam)'),
        two('${f2(sum(l.where((r) => r['tur'] == 'giren'), (r) => toD(r['litre'])))} L', 'Depoya giren'),
        two('${f2(sum(l.where((r) => r['tur'] == 'cikan'), (r) => toD(r['litre'])))} L', 'Depodan çıkan'),
        two('${f2(sum(l.where((r) => r['tur'] == 'alim'), (r) => toD(r['litre'])))} L', 'Dışarıdan'),
      ]),
      _sumRow([
        two(tl(sum(l.where((r) => r['tur'] != 'cikan'), (r) => toD(r['tutar']))), 'Alım tutarı (bilgi)'),
        two(tl(S.mazotOde(ayF.value)), 'Gidere işlenen'),
        two(tl(S.mazotBorcu), 'Kalan mazot borcu', ac: orange),
      ]),
    ]),
    monthSum: (l) => '${f2(sum(l, (r) => toD(r['litre'])))} L',
    onAdd: (c, k) => editRec(c, S.mazot, 'mazot kaydı', mazotFl(),
        defaults: k == 'Depo girişleri' ? {'tur': 'giren'} : (k == 'Dışarıdan alımlar' ? {'tur': 'alim'} : {'tur': 'cikan', if (k != null && k != 'Makina belirtilmemiş') 'makina': k})),
  );
  @override
  Widget build(BuildContext context) => GroupView(cfg);
}

class TankIcon extends StatelessWidget {
  final Color color;
  final double fill;
  const TankIcon(this.color, this.fill, {super.key});
  @override
  Widget build(BuildContext context) => SizedBox(width: 36, height: 44, child: CustomPaint(painter: _TankPainter(color, fill)));
}

class _TankPainter extends CustomPainter {
  final Color c;
  final double f;
  _TankPainter(this.c, this.f);
  @override
  void paint(Canvas cv, Size s) {
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(2, 8, s.width - 4, s.height - 10), const Radius.circular(9));
    cv.drawRRect(body, Paint()..color = c.withAlpha(40));
    cv.save();
    cv.clipRRect(body);
    final h = (s.height - 10) * f.clamp(0.1, 1.0);
    cv.drawRect(Rect.fromLTWH(2, 8 + (s.height - 10) - h, s.width - 4, h), Paint()..color = c);
    cv.restore();
    cv.drawRRect(body, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = c);
    cv.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(s.width / 2 - 6, 0, 12, 7), const Radius.circular(3)), Paint()..color = c);
  }

  @override
  bool shouldRepaint(covariant _TankPainter o) => o.c != c || o.f != f;
}

// ============================ MÜŞTERİ ============================
class MusteriTab extends StatefulWidget {
  const MusteriTab({super.key});
  @override
  State<MusteriTab> createState() => _MusteriState();
}

class _MusteriState extends State<MusteriTab> {
  String q = '', seg = 'hepsi';
  String? cat;

  Widget _satir(String a, String b, [Color? c]) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(children: [
          Expanded(child: Text(a, style: const TextStyle(fontSize: 12, color: grey))),
          Text(b, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c)),
        ]),
      );

  Widget _katCard(String? key, String label, Color col, List<CStat> list) {
    final b = list.fold<double>(0.0, (a, s) => a + s.borc), a = list.fold<double>(0.0, (x, s) => x + s.alinan), k = b - a;
    final on = cat == key;
    return GestureDetector(
      onTap: () => setState(() => cat = key),
      child: Container(
        width: 205,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: on ? col.withAlpha(28) : cardC(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: on ? col : lineC(context), width: on ? 2 : 1)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(radius: 5, backgroundColor: col),
            const SizedBox(width: 6),
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
            Text('${list.length} kişi', style: const TextStyle(fontSize: 11, color: grey)),
          ]),
          const SizedBox(height: 6),
          _satir('Toplam iş', tl(b)),
          _satir('Ödenen', tl(a), green),
          _satir('Kalan', tl(k), k > 0.5 ? red : green),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: S,
      builder: (c, _) {
        final every = S.cust.values.toList();
        final all = every.where((s) => cat == null || (S.mCat(s.name).isEmpty ? '__none' : S.mCat(s.name)) == cat).toList();
        int cnt(String d) => d == 'hepsi' ? all.length : all.where((s) => s.durum == d).length;
        final k = norm(q);
        final l = (k.isNotEmpty ? all.where((s) => norm(s.name).contains(k)) : (seg == 'hepsi' ? all : all.where((s) => s.durum == seg))).toList();
        l.sort((a, b) => seg == 'tam' && k.isEmpty ? b.borc.compareTo(a.borc) : b.kalan.compareTo(a.kalan));
        final segs = ['hepsi', 'hic', 'kismen', 'tam', if (every.any((s) => s.durum == 'yok')) 'yok'];
        final y = S.year;
        final noCat = every.where((s) => S.mCat(s.name).isEmpty).toList();
        final realCat = cat != null && cat != '__none';
        return Scaffold(
          appBar: AppBar(title: const Text('Müşteriler'), actions: [
            IconButton(icon: const Icon(Icons.category_outlined), tooltip: 'Kategorileri yönet', onPressed: () => push(c, const KatPage(false))),
            IconButton(icon: const Icon(Icons.campaign_outlined), tooltip: 'Tahsilat listesi (WhatsApp)', onPressed: () => push(c, const TahsilatPage())),
          ]),
          body: Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 8), child: searchBox((v) => setState(() => q = v), 'Müşteri ara…')),
            SizedBox(
              height: 128,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                _katCard(null, 'Tüm işler', inkNavy, every),
                for (final kt in S.mKatList) _katCard(kt, kt, katColor(kt), every.where((s) => S.mCat(s.name) == kt).toList()),
                if (S.mKatList.isNotEmpty && noCat.isNotEmpty) _katCard('__none', 'Kategorisiz', grey, noCat),
              ]),
            ),
            if (realCat)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.payments),
                    label: Text('"$cat" adına tahsilat al (borca göre dağıt)'),
                    onPressed: () => katTahsilat(c, cat!),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            SizedBox(
              height: 42,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                for (final d in segs)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      selectedColor: (d == 'hepsi' ? inkNavy : durumRenk[d]!).withAlpha(45),
                      avatar: CircleAvatar(radius: 5, backgroundColor: d == 'hepsi' ? inkNavy : durumRenk[d]),
                      label: Text('${d == 'hepsi' ? 'Hepsi' : durumAd[d]} (${cnt(d)})', style: const TextStyle(fontWeight: FontWeight.w600)),
                      selected: seg == d && k.isEmpty,
                      onSelected: (_) => setState(() {
                        seg = d;
                        q = '';
                      }),
                    ),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
              child: Row(children: [
                const Icon(Icons.star, size: 14, color: gold),
                const SizedBox(width: 4),
                Expanded(child: Text('Altın çerçeve: $y yılında en çok iş yapılan 5 müşteri', style: const TextStyle(fontSize: 12, color: grey))),
              ]),
            ),
            Expanded(
              child: l.isEmpty
                  ? Center(child: Text(S.musteriler.isEmpty ? 'Henüz müşteri yok. Sağ alttaki düğmeyle ekleyin.' : 'Bu grupta müşteri yok'))
                  : ListView.builder(padding: const EdgeInsets.fromLTRB(12, 4, 12, 90), itemCount: l.length, itemBuilder: (c, i) => musteriCard(c, l[i].name)),
            ),
          ]),
          floatingActionButton: FloatingActionButton(
            onPressed: () async {
              final n0 = await askName(c, 'Yeni müşteri');
              if (n0 == null || n0.isEmpty || !c.mounted) return;
              final n = await confirmSimilar(c, n0, S.musteriler, 'Müşteri');
              if (n == null || n.isEmpty) return;
              if (S.musteriler.any((x) => norm(x) == norm(n))) {
                if (c.mounted) msg(c, '"$n" zaten kayıtlı.');
                return;
              }
              S.musteriler.add(n);
              S.commit();
            },
            child: const Icon(Icons.person_add),
          ),
        );
      });
}

class MusteriDetay extends StatelessWidget {
  final String name;
  const MusteriDetay(this.name, {super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: S,
      builder: (c, _) {
        final l = S.isler.where((r) => norm(r['musteri'] ?? '') == norm(name)).toList();
        final s = S.cust[norm(name)] ?? CStat(name);
        final rk = S.rank(name);
        final cfg = GCfg(
            title: name, selLabel: '', items: () => l, keyOf: (r) => name, allKeys: () => [], sorts: [], card: (c, g) => const SizedBox(), rec: jobRec, summary: (x) => const SizedBox(),
            monthSum: (x) => 'borç ${tl(sum(x, borc))} · alınan ${tl(sum(x, (r) => toD(r['alinan'])))}', onAdd: (c, k) {});
        return Scaffold(
          appBar: AppBar(title: Text(name, overflow: TextOverflow.ellipsis), actions: [
            IconButton(icon: const Icon(Icons.ios_share), tooltip: 'Ekstre', onPressed: () => exportSheet(c, 'Ekstre - $name', (a, b) => repEkstre(name))),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'r') {
                  final n = await askName(c, 'Müşteri adı', name);
                  if (n == null || n.isEmpty) return;
                  for (final r in l) {
                    r['musteri'] = n;
                  }
                  final i = S.musteriler.indexWhere((x) => norm(x) == norm(name));
                  if (i >= 0) S.musteriler[i] = n;
                  if (S.telefon.containsKey(norm(name))) S.telefon[norm(n)] = S.telefon.remove(norm(name))!;
                  if (S.mKat.containsKey(norm(name))) S.mKat[norm(n)] = S.mKat.remove(norm(name))!;
                  S.commit();
                  if (c.mounted) Navigator.pop(c);
                } else if (l.isNotEmpty) {
                  msg(c, 'Bu müşterinin ${l.length} kaydı var. Önce kayıtları silin veya başka müşteriye taşıyın.');
                } else {
                  S.musteriler.removeWhere((x) => norm(x) == norm(name));
                  S.commit();
                  Navigator.pop(c);
                }
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'r', child: Text('Adını değiştir')), PopupMenuItem(value: 'd', child: Text('Müşteriyi sil'))],
            ),
          ]),
          body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 40), children: [
            Box(
              color: rk >= 0 ? goldBg : null,
              border: rk >= 0 ? gold : null,
              child: Row(children: [
                Avatar(name),
                const SizedBox(width: 12),
                Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
                Wrap(spacing: 6, children: [if (rk >= 0) Pill('★ ${rk + 1}. büyük müşteri', gold), Pill(durumAd[s.durum]!, durumRenk[s.durum]!)]),
              ]),
            ),
            Row(children: [
              Expanded(child: StatCard('Borç', tl(s.borc), icon: Icons.work_outline)),
              const SizedBox(width: 8),
              Expanded(child: StatCard('Alınan', tl(s.alinan), color: green, icon: Icons.south_west)),
              const SizedBox(width: 8),
              Expanded(child: StatCard('Kalan', tl(s.kalan), color: s.kalan > 0.5 ? red : green, icon: Icons.hourglass_bottom)),
            ]),
            const SizedBox(height: 10),
            if (s.kalan > 0.5 && s.oldest != null) Align(alignment: Alignment.centerLeft, child: agePill(s)),
            const SizedBox(height: 4),
            Box(
              pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              bottom: 6,
              onTap: () async {
                final t = await askName(c, 'Telefon (WhatsApp için)', S.telefon[norm(name)] ?? '');
                if (t == null) return;
                if (t.isEmpty) {
                  S.telefon.remove(norm(name));
                } else {
                  S.telefon[norm(name)] = t;
                }
                S.commit();
              },
              child: Row(children: [
                const Icon(Icons.phone, size: 18, color: grey),
                const SizedBox(width: 8),
                Expanded(child: Text((S.telefon[norm(name)] ?? '').isEmpty ? 'Telefon ekle (WhatsApp için)' : S.telefon[norm(name)]!, style: TextStyle(color: (S.telefon[norm(name)] ?? '').isEmpty ? grey : null))),
                const Icon(Icons.edit, size: 16, color: grey),
              ]),
            ),
            Box(
              pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              bottom: 6,
              onTap: () async {
                final v = await pickCat(c, false, S.mCat(name));
                if (v == null) return;
                if (v.isEmpty) {
                  S.mKat.remove(norm(name));
                } else {
                  S.mKat[norm(name)] = v;
                }
                S.commit();
              },
              child: Row(children: [
                const Icon(Icons.label_outline, size: 18, color: grey),
                const SizedBox(width: 8),
                Expanded(child: Text(S.mCat(name).isEmpty ? 'Kategori ata (örn. Belediye, Şahıs, Firma)' : S.mCat(name), style: TextStyle(color: S.mCat(name).isEmpty ? grey : null))),
                const Icon(Icons.edit, size: 16, color: grey),
              ]),
            ),
            Box(
              pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              bottom: 6,
              onTap: () => sozDuzenle(c, name),
              child: Row(children: [
                const Icon(Icons.event_note, size: 18, color: grey),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                        (S.soz[norm(name)] ?? '').length >= 10 ? 'Ödeme sözü: ${dshow(S.soz[norm(name)]!.substring(0, 10))}${S.soz[norm(name)]!.length > 11 ? ' · ${S.soz[norm(name)]!.substring(11)}' : ''}' : 'Ödeme sözü / tarih ekle',
                        style: TextStyle(color: (S.soz[norm(name)] ?? '').length >= 10 ? null : grey))),
                const Icon(Icons.edit, size: 16, color: grey),
              ]),
            ),
            Row(children: [
              Expanded(child: FilledButton.icon(onPressed: () => editRec(c, S.isler, 'tahsilat', tahsilatFl(), defaults: {'musteri': name, 'aciklama': 'Tahsilat'}), icon: const Icon(Icons.payments), label: const Text('Tahsilat'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: () => editRec(c, S.isler, 'iş', isFl(), defaults: {'musteri': name}), icon: const Icon(Icons.add), label: const Text('İş ekle'))),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                tooltip: 'WhatsApp ile hatırlat',
                onPressed: () => showModalBottomSheet(
                    context: c,
                    builder: (x) => SafeArea(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            ListTile(
                                leading: const Icon(Icons.receipt_long, color: green),
                                title: const Text('Detaylı hesap özeti gönder'),
                                subtitle: const Text('Çalışma saati, toplam, ödenen, kalan, iş listesi'),
                                onTap: () {
                                  Navigator.pop(x);
                                  whatsapp(c, S.telefon[norm(name)], waEkstre(name));
                                }),
                            ListTile(
                                leading: const Icon(Icons.notifications_active_outlined, color: orange),
                                title: const Text('Kısa ödeme hatırlatması'),
                                onTap: () {
                                  Navigator.pop(x);
                                  whatsapp(c, S.telefon[norm(name)], hatirlat(s));
                                }),
                          ]),
                        )),
                icon: const Icon(Icons.chat),
              ),
            ]),
            ...detailRows(c, cfg, l),
          ]),
        );
      });
}

// ============================ MAKİNA ============================
class MakinaTab extends StatelessWidget {
  const MakinaTab({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: Listenable.merge([S, ayF]),
      builder: (c, _) {
        final l = S.makinaStat(ayF.value)..sort((a, b) => b.gelir.compareTo(a.gelir));
        final genelL = {for (final x in S.makinaStat(0)) norm(x.name): x.lPerUnit};
        return Scaffold(
          appBar: AppBar(title: const Text('Makinalar'), actions: [
            IconButton(
                icon: Badge(isLabelVisible: S.belgeUyari.isNotEmpty, label: Text('${S.belgeUyari.length}'), child: const Icon(Icons.badge_outlined)),
                tooltip: 'Belgeler (muayene, sigorta…)',
                onPressed: () => push(c, const BelgePage())),
            const AyDrop(),
          ]),
          body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
            if (l.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('Henüz makina yok. Sağ alttaki + ile ekleyin.', style: TextStyle(color: grey)))),
            for (final s in l)
              Box(
                onTap: () => push(c, MakinaDetay(s.name)),
                child: Row(children: [
                  MAvatar(s.name),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      Text('${s.active ? s.calisma : 'Kayıt yok'} · ${f2(s.litre)} L yakıt', style: const TextStyle(fontSize: 12, color: grey)),
                      if (ayF.value != 0 && s.lPerUnit > 0 && (genelL[norm(s.name)] ?? 0) > 0 && s.lPerUnit > 1.3 * genelL[norm(s.name)]!)
                        Padding(padding: const EdgeInsets.only(top: 3), child: Pill('⛽ Yakıt tüketimi yüksek (${f2(s.lPerUnit)} L/birim, ortalama ${f2(genelL[norm(s.name)]!)})', red)),
                    ]),
                  ),
                  two(tl(s.gelir), 'kâr ${tl(s.kar)}', bc: signC(s.kar)),
                  const Icon(Icons.chevron_right, color: grey),
                ]),
              ),
          ]),
          floatingActionButton: FloatingActionButton(
            onPressed: () async {
              final n0 = await askName(c, 'Yeni makina');
              if (n0 == null || n0.isEmpty || !c.mounted) return;
              final n = await confirmSimilar(c, n0, S.makinalar, 'Makina');
              if (n == null || n.isEmpty || S.makinalar.any((x) => norm(x) == norm(n)) || !c.mounted) return;
              final idx = nextColorIdx();
              if (!c.mounted) return;
              final pick = await pickColor(c, idx);
              S.makinalar.add(n);
              S.renk[norm(n)] = '${pick ?? idx}';
              S.commit();
            },
            child: const Icon(Icons.add),
          ),
        );
      });
}

class MakinaDetay extends StatelessWidget {
  final String name;
  const MakinaDetay(this.name, {super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: Listenable.merge([S, ayF]),
      builder: (c, _) {
        final k = norm(name);
        final jobs = S.byMonth(S.isler, ayF.value).where((r) => norm(r['makina'] ?? '') == k).toList();
        final fuel = S.byMonth(S.mazot, ayF.value).where((r) => r['tur'] != 'giren' && norm(r['makina'] ?? '') == k).toList();
        final st = S.makinaStat(ayF.value).firstWhere((s) => norm(s.name) == k, orElse: () => MStat(name));
        final jc = GCfg(title: '', selLabel: '', items: () => jobs, keyOf: (r) => name, allKeys: () => [], sorts: [], card: (c, g) => const SizedBox(), rec: jobRec, summary: (x) => const SizedBox(), monthSum: (x) => tl(sum(x, borc)), onAdd: (c, k) {});
        final fc = GCfg(
            title: '', selLabel: '', items: () => fuel, keyOf: (r) => name, allKeys: () => [], sorts: [], card: (c, g) => const SizedBox(), summary: (x) => const SizedBox(), monthSum: (x) => '${f2(sum(x, (r) => toD(r['litre'])))} L', onAdd: (c, k) {},
            rec: (c, r) => Box(
                  pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  bottom: 6,
                  onTap: () => editRec(c, S.mazot, 'mazot kaydı', mazotFl(), rec: r),
                  child: Row(children: [
                    Icon(r['tur'] == 'alim' ? Icons.shopping_cart_outlined : Icons.local_gas_station, color: r['tur'] == 'alim' ? const Color(0xFF00897B) : orange, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(dshow(r['tarih']), style: const TextStyle(fontWeight: FontWeight.w600)), Text(r['tur'] == 'alim' ? 'Dışarıdan alım' : 'Depodan', style: const TextStyle(fontSize: 12, color: grey))])),
                    two('${r['litre'] ?? '0'} L', toD(r['tutar']) > 0 ? tl(toD(r['tutar'])) : ''),
                  ]),
                ));
        return Scaffold(
          appBar: AppBar(title: Text(name), actions: [
            const AyDrop(),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'r') {
                  final n = await askName(c, 'Makina adı', name);
                  if (n == null || n.isEmpty) return;
                  for (final r in [...S.isler, ...S.mazot, ...S.bakim]) {
                    if (norm(r['makina'] ?? '') == k) r['makina'] = n;
                  }
                  final i = S.makinalar.indexWhere((e) => norm(e) == k);
                  if (i >= 0) S.makinalar[i] = n;
                  if (S.foto.containsKey(k)) S.foto[norm(n)] = S.foto.remove(k)!;
                  S.renk[norm(n)] = '${mIdx(name)}';
                  S.renk.remove(k);
                  S.commit();
                  if (c.mounted) Navigator.pop(c);
                } else {
                  S.makinalar.removeWhere((e) => norm(e) == k);
                  S.commit();
                  Navigator.pop(c);
                }
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'r', child: Text('Adını değiştir')), PopupMenuItem(value: 'd', child: Text('Listeden sil (kayıtlar kalır)'))],
            ),
          ]),
          body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
            machinePhoto(c, name),
            Box(
              pad: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              onTap: () async {
                final i = await pickColor(c, mIdx(name));
                if (i != null) {
                  S.renk[k] = '$i';
                  S.commit();
                }
              },
              child: Row(children: [
                CircleAvatar(radius: 12, backgroundColor: mColor(name)),
                const SizedBox(width: 12),
                const Expanded(child: Text('Makina rengi (yakıt depo simgesi ve listelerde)', style: TextStyle(fontWeight: FontWeight.w600))),
                const Text('Değiştir', style: TextStyle(color: grey)),
              ]),
            ),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.1,
              children: [
                StatCard('Çalışma', st.active ? st.calisma : '-', icon: Icons.timer_outlined),
                StatCard('Gelir', tl(st.gelir), icon: Icons.trending_up),
                StatCard('Yakıt (depo + dışarıdan)', '${f2(st.litre)} L', icon: Icons.local_gas_station),
                StatCard('Kâr', tl(st.kar), color: signC(st.kar), icon: Icons.account_balance_wallet_outlined),
              ],
            ),
            secTitle('Yakıt kayıtları (depodan + dışarıdan alım)'),
            if (fuel.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Kayıt yok', style: TextStyle(color: grey))),
            ...detailRows(c, fc, fuel),
            secTitle('İş kayıtları'),
            if (jobs.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Kayıt yok', style: TextStyle(color: grey))),
            ...detailRows(c, jc, jobs),
          ]),
          floatingActionButton: FloatingActionButton(
            onPressed: () => showModalBottomSheet(
                context: c,
                builder: (x) => SafeArea(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        ListTile(leading: const Icon(Icons.construction), title: const Text('İş ekle'), onTap: () {
                          Navigator.pop(x);
                          editRec(c, S.isler, 'iş', isFl(), defaults: {'makina': name});
                        }),
                        ListTile(leading: const Icon(Icons.local_gas_station), title: const Text('Yakıt çıkışı ekle (depodan)'), onTap: () {
                          Navigator.pop(x);
                          editRec(c, S.mazot, 'mazot kaydı', mazotFl(), defaults: {'tur': 'cikan', 'makina': name});
                        }),
                        ListTile(leading: const Icon(Icons.shopping_cart_outlined), title: const Text('Dışarıdan yakıt alımı ekle'), onTap: () {
                          Navigator.pop(x);
                          editRec(c, S.mazot, 'mazot kaydı', mazotFl(), defaults: {'tur': 'alim', 'makina': name});
                        }),
                      ]),
                    )),
            child: const Icon(Icons.add),
          ),
        );
      });
}

// ============================ ÖZET ============================
class OzetTab extends StatelessWidget {
  const OzetTab({super.key});

  Widget _chart() {
    final b = List.generate(12, (i) => sum(S.isler.where((r) => mon(r) == i + 1 && (r['tarih'] ?? '').startsWith(S.year)), borc));
    final g = List.generate(12, (i) => sum(S.giderler.where((r) => mon(r) == i + 1 && (r['tarih'] ?? '').startsWith(S.year)), (r) => toD(r['tutar'])));
    final mx = [...b, ...g].fold(0.0, (a, v) => v > a ? v : a);
    Widget bar(double v, Color c) => Container(width: 8, height: mx == 0 ? 0 : 100 * v / mx, decoration: BoxDecoration(color: c, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))));
    return Box(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Aylık iş ve gider', style: TextStyle(fontWeight: FontWeight.w700))),
          const CircleAvatar(radius: 4, backgroundColor: blue),
          const Text('  İş   ', style: TextStyle(fontSize: 12, color: grey)),
          const CircleAvatar(radius: 4, backgroundColor: red),
          const Text('  Gider', style: TextStyle(fontSize: 12, color: grey)),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < 12; i++)
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(height: 100, child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [bar(b[i], blue), const SizedBox(width: 2), bar(g[i], red)])),
                const SizedBox(height: 4),
                Text(aylar[i + 1].substring(0, 3), style: const TextStyle(fontSize: 9, color: grey)),
              ]),
            ),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: Listenable.merge([S, ayF]),
      builder: (c, _) {
        final m = ayF.value;
        final js = S.byMonth(S.isler, m);
        final borcT = sum(js, borc), alinan = sum(js, (r) => toD(r['alinan']));
        final kalanAll = sum(S.isler, borc) - sum(S.isler, (r) => toD(r['alinan']));
        final gider = sum(S.byMonth(S.giderler, m), (r) => toD(r['tutar']));
        final alim = S.alimTl(m), ode = S.mazotOde(m), borcMz = S.mazotBorcu;
        final net = borcT - gider, kasa = alinan - gider;
        final ms = S.makinaStat(m).where((s) => s.active).toList();
        final borclu = (S.cust.values.where((s) => s.kalan > 0.5).toList()..sort((a, b) => b.kalan.compareTo(a.kalan))).take(5).toList();
        return Scaffold(
          appBar: AppBar(title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Özet ve Analiz'), Text('Sürüm 12 · 2.2.0+11 · ${Nat.ad}', style: const TextStyle(fontSize: 10.5, color: Colors.white70, fontWeight: FontWeight.w400))]), actions: [
            const AyDrop(),
            PopupMenuButton<String>(
              onSelected: (v) => _menu(c, v),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'a', child: Text('Ayarlar (firma, logo)')),
                PopupMenuItem(value: 'b', child: Text('Yedeği panoya kopyala')),
                PopupMenuItem(value: 'r', child: Text('Panodaki yedeği geri yükle')),
                PopupMenuItem(value: 'f', child: Text('Yedeği dosya olarak paylaş')),
                PopupMenuItem(value: 'd', child: Text('Yedeği dosyadan yükle')),
                PopupMenuItem(value: 'x', child: Text('Excel verisini yükle (örnek)')),
                PopupMenuItem(value: 'e', child: Text('Tüm verileri sil (boş başla)')),
              ],
            ),
          ]),
          body: ListView(padding: const EdgeInsets.all(12), children: [
            bakimBanner(),
            alacakBanner(),
            uyariBannerlari(),
            GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: (MediaQuery.of(c).size.width ~/ 320).clamp(2, 6), mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 100),
              children: [
                StatCard('Toplam iş (borç)', tl(borcT), icon: Icons.work_outline),
                StatCard('Alınan', tl(alinan), color: green, icon: Icons.south_west),
                StatCard('Müşterilerde kalan (tüm zamanlar)', tl(kalanAll), color: red, icon: Icons.hourglass_bottom),
                StatCard('Depoda mazot', '${f2(S.depo)} L', icon: Icons.local_gas_station),
                StatCard('Giderler', tl(gider), color: red, icon: Icons.receipt_long),
                StatCard('Mazot borcu (bilgi, gider değil)', tl(borcMz), color: orange, icon: Icons.shopping_cart_outlined),
                StatCard('Net kâr (iş – gider)', tl(net), color: signC(net), icon: Icons.trending_up),
                StatCard('Kasa (alınan – gider)', tl(kasa), color: signC(kasa), icon: Icons.account_balance_wallet_outlined),
              ],
            ),
            const SizedBox(height: 10),
            Box(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [Icon(Icons.local_gas_station, size: 18, color: orange), SizedBox(width: 6), Text('Mazot (sadece bilgi)', style: TextStyle(fontWeight: FontWeight.w700))]),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [two(tl(alim), 'Alım tutarı'), two(tl(ode), 'Gidere işlenen'), two(tl(borcMz), 'Kalan borç (genel)', ac: orange)]),
                const SizedBox(height: 6),
                const Text('Alım tutarı gider sayılmaz. Parayı verince Gider\'e "mazot" kalemiyle (veya "mazot ödemesi: Evet" seçerek) işleyin, borçtan düşer.', style: TextStyle(fontSize: 11.5, color: grey)),
              ]),
            ),
            Builder(
                builder: (c) => Box(
                      color: const Color(0xFFEFF6FF),
                      border: blue,
                      onTap: () => push(c, const KarlilikPage()),
                      child: Row(children: [
                        const Icon(Icons.insights, color: blue),
                        const SizedBox(width: 10),
                        const Expanded(child: Text('Kârlılık analizi: Bu iş bana gerçekten ne kazandırıyor?', style: TextStyle(fontWeight: FontWeight.w700))),
                        const Icon(Icons.chevron_right, color: grey),
                      ]),
                    )),
            Builder(
                builder: (c) => Box(
                      onTap: () => teklifHazirla(c),
                      child: Row(children: [
                        const Icon(Icons.request_quote, color: green),
                        const SizedBox(width: 10),
                        const Expanded(child: Text('Fiyat teklifi hazırla (PDF)', style: TextStyle(fontWeight: FontWeight.w700))),
                        const Icon(Icons.chevron_right, color: grey),
                      ]),
                    )),
            secTitle('Raporlar (PDF / Excel)'),
            Box(
              child: Row(children: [
                for (final e in [
                  ['Müşteri\nraporu', 'm', Icons.groups],
                  ['Gider\nraporu', 'g', Icons.receipt_long],
                  ['Makina\nraporu', 'k', Icons.precision_manufacturing],
                  ['Aylık\nözet', 'a', Icons.insights]
                ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: amber, foregroundColor: Colors.white, minimumSize: const Size(0, 70), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        onPressed: () {
                          if (e[1] == 'm') {
                            exportSheet(c, 'Müşteri raporu', repMusteriSel, scopes: const ['Tüm müşteriler', 'Sadece borçlular'], selLabel: 'Müşteri / kategori seç', selOptions: musteriSelOpts, musteri: true);
                          } else if (e[1] == 'g') {
                            exportSheet(c, 'Gider raporu (${aylar[m]})', (sc, sel) => repGider(m, sel), selLabel: 'Kalem / kategori seç', selOptions: giderSelOpts);
                          } else if (e[1] == 'k') {
                            exportSheet(c, 'Makina raporu (${aylar[m]})', (sc, sel) => repMakina(m, sel), selLabel: 'Makina seç', selOptions: () => [...S.makinalar]);
                          } else {
                            exportSheet(c, 'Aylık yönetim özeti (${aylar[m]})', (sc, sel) => repAylik(m));
                          }
                        },
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(e[2] as IconData, size: 20), const SizedBox(height: 4), Text(e[0] as String, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))]),
                      ),
                    ),
                  ),
              ]),
            ),
            secTitle('Aylık görünüm'),
            _chart(),
            secTitle('Alacak yaşlandırma'),
            agingCard(),
            secTitle('En çok borçlu 5 müşteri'),
            if (borclu.isEmpty) const Box(child: Text('Borçlu müşteri yok 🎉')),
            for (final s in borclu)
              Box(
                pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                bottom: 6,
                onTap: () => push(c, MusteriDetay(s.name)),
                child: Row(children: [
                  Avatar(s.name),
                  const SizedBox(width: 10),
                  Expanded(child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                  Text(tl(s.kalan), style: const TextStyle(fontWeight: FontWeight.w700, color: red)),
                ]),
              ),
            secTitle('${S.year} yılının en büyük 5 müşterisi'),
            for (var i = 0; i < S.top5.length; i++)
              Box(
                color: goldBg,
                border: gold,
                pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                bottom: 6,
                onTap: () => push(c, MusteriDetay(S.top5[i].name)),
                child: Row(children: [
                  Pill('★ ${i + 1}', gold),
                  const SizedBox(width: 10),
                  Expanded(child: Text(S.top5[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                  Text(tl(S.top5[i].yil), style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
            secTitle('Makina analizi'),
            Box(
              pad: EdgeInsets.zero,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 18,
                  headingTextStyle: const TextStyle(fontWeight: FontWeight.w700, color: grey, fontSize: 12),
                  columns: const [
                    DataColumn(label: Text('Makina')),
                    DataColumn(label: Text('Çalışma')),
                    DataColumn(label: Text('Mazot L'), numeric: true),
                    DataColumn(label: Text('L/birim'), numeric: true),
                    DataColumn(label: Text('Gelir'), numeric: true),
                    DataColumn(label: Text('Mazot ₺'), numeric: true),
                    DataColumn(label: Text('Kâr'), numeric: true),
                  ],
                  rows: [
                    for (final s in ms)
                      DataRow(cells: [
                        DataCell(Row(children: [CircleAvatar(radius: 5, backgroundColor: mColor(s.name)), const SizedBox(width: 6), Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600))])),
                        DataCell(Text(s.calisma)),
                        DataCell(Text(f2(s.litre))),
                        DataCell(Text(f2(s.lPerUnit), style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text(tl(s.gelir, ''))),
                        DataCell(Text(tl(s.mazotTl, ''))),
                        DataCell(Text(tl(s.kar, ''), style: TextStyle(color: signC(s.kar), fontWeight: FontWeight.w600))),
                      ]),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('L/birim: litre ÷ (saat veya sefer). Mazot ₺ = litre × fiyatı girilmiş alımların ortalama litre fiyatı.', style: TextStyle(color: grey, fontSize: 12)),
            ),
          ]),
        );
      });

  Future<void> _menu(BuildContext c, String v) async {
    if (v == 'a') {
      push(c, const AyarPage());
    } else if (v == 'f') {
      try {
        await yedekAl(c);
      } catch (e) {
        if (c.mounted) msg(c, 'Hata: $e');
      }
    } else if (v == 'd') {
      if (!Nat.files) {
        if (c.mounted) msg(c, 'Dosyadan yükleme bu sürümde yok (temel sürüm). Panodan yüklemeyi kullanın.');
        return;
      }
      final ok0 = await showDialog<bool>(
          context: c,
          builder: (x) => AlertDialog(
                title: const Text('Yedek yüklensin mi?'),
                content: const Text('Mevcut tüm kayıtların yerine seçtiğiniz yedek dosyasının içeriği gelir.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(x, false), child: const Text('Vazgeç')),
                  FilledButton(onPressed: () => Navigator.pop(x, true), child: const Text('Dosya seç')),
                ],
              ));
      if (ok0 != true) return;
      final t = await Nat.pickJson();
      if (t == null) return;
      final ok = S.restore(t);
      if (c.mounted) msg(c, ok ? 'Yedek yüklendi.' : 'Seçilen dosya geçerli bir yedek değil.');
    } else if (v == 'b') {
      await Clipboard.setData(ClipboardData(text: S.export()));
      S.ayar['son_yedek'] = todayIso();
      S.commit();
      if (c.mounted) msg(c, 'Yedek panoya kopyalandı. Bir yere yapıştırıp saklayın.');
    } else if (v == 'r') {
      final d = await Clipboard.getData(Clipboard.kTextPlain);
      final ok = S.restore(d?.text ?? '');
      if (c.mounted) msg(c, ok ? 'Yedek geri yüklendi.' : 'Panoda geçerli bir yedek yok.');
    } else {
      final del = v == 'e';
      final ok = await showDialog<bool>(
          context: c,
          builder: (x) => AlertDialog(
                  title: Text(del ? 'Tüm veriler silinsin mi?' : 'Excel verisi yüklensin mi?'),
                  content: Text(del
                      ? 'Tüm müşteri, iş, gider, mazot ve bakım kayıtları silinir; uygulama boş başlar. Bu işlem geri alınamaz.'
                      : 'Mevcut tüm kayıtlar silinir ve Excel dosyanızdan aktarılan örnek veri yüklenir.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(x, false), child: const Text('Vazgeç')),
                    FilledButton(onPressed: () => Navigator.pop(x, true), child: Text(del ? 'Sil' : 'Yükle')),
                  ]));
      if (ok == true) {
        if (del) {
          await S.clearAll();
        } else {
          await S.reset();
        }
      }
    }
  }
}

// ============================ FOTOĞRAF / WHATSAPP ============================
Future<String?> pickPhoto(BuildContext c, String key) async {
  final desk = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  final src = desk ? ImageSource.gallery : await showModalBottomSheet<ImageSource>(
      context: c,
      builder: (x) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(leading: const Icon(Icons.photo_library), title: const Text('Galeriden seç'), onTap: () => Navigator.pop(x, ImageSource.gallery)),
              ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Kamera ile çek'), onTap: () => Navigator.pop(x, ImageSource.camera)),
            ]),
          ));
  if (src == null) return null;
  try {
    final img = await ImagePicker().pickImage(source: src, maxWidth: 1400, imageQuality: 85);
    if (img == null) return null;
    final d = Directory('$docsDir/fotolar');
    if (!await d.exists()) await d.create(recursive: true);
    final dest = '${d.path}/${key.replaceAll(RegExp(r'[^a-z0-9]'), '')}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(img.path).copy(dest);
    return dest;
  } catch (e) {
    if (c.mounted) msg(c, 'Fotoğraf alınamadı: $e');
    return null;
  }
}

class MAvatar extends StatelessWidget {
  final String name;
  const MAvatar(this.name, {super.key});
  @override
  Widget build(BuildContext context) {
    final col = mColor(name);
    final p = S.foto[norm(name)];
    if (p != null && File(fp(p)).existsSync()) {
      return Container(padding: const EdgeInsets.all(2), decoration: BoxDecoration(shape: BoxShape.circle, color: col), child: CircleAvatar(radius: 20, backgroundImage: FileImage(File(fp(p)))));
    }
    return CircleAvatar(radius: 22, backgroundColor: col.withAlpha(45), child: Icon(Icons.precision_manufacturing, color: col, size: 22));
  }
}

Widget machinePhoto(BuildContext c, String name) {
  final k = norm(name);
  final p = S.foto[k];
  final has = p != null && File(fp(p)).existsSync();
  return GestureDetector(
    onTap: () => showModalBottomSheet(
        context: c,
        builder: (x) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(
                    leading: const Icon(Icons.add_a_photo),
                    title: Text(has ? 'Fotoğrafı değiştir' : 'Fotoğraf ekle'),
                    onTap: () async {
                      Navigator.pop(x);
                      final f = await pickPhoto(c, k);
                      if (f != null) {
                        S.foto[k] = f;
                        S.commit();
                      }
                    }),
                if (has)
                  ListTile(
                      leading: const Icon(Icons.delete_outline, color: red),
                      title: const Text('Fotoğrafı kaldır'),
                      onTap: () {
                        Navigator.pop(x);
                        S.foto.remove(k);
                        S.commit();
                      }),
              ]),
            )),
    child: Container(
      height: 180,
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: cardC(c), borderRadius: BorderRadius.circular(16), border: Border.all(color: lineC(c))),
      child: has
          ? Stack(fit: StackFit.expand, children: [
              Image.file(File(fp(p)), fit: BoxFit.cover),
              const Positioned(right: 8, bottom: 8, child: CircleAvatar(backgroundColor: Colors.black54, child: Icon(Icons.edit, color: Colors.white))),
            ])
          : const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add_a_photo_outlined, size: 40, color: grey),
              SizedBox(height: 6),
              Text('Makina fotoğrafı ekle', style: TextStyle(color: grey)),
            ])),
    ),
  );
}

Future<void> whatsapp(BuildContext c, String? phone, String text) async {
  var p = (phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  if (p.startsWith('00')) {
    p = p.substring(2);
  } else if (p.startsWith('0')) {
    p = '90${p.substring(1)}';
  } else if (p.length == 10) {
    p = '90$p';
  }
  final uri = Uri.parse('https://wa.me/$p?text=${Uri.encodeComponent(text)}');
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && c.mounted) msg(c, 'WhatsApp açılamadı.');
  } catch (_) {
    if (c.mounted) msg(c, 'WhatsApp açılamadı.');
  }
}

String hatirlat(CStat s) {
  final f = S.ayar['firma'] ?? '';
  return 'Merhaba ${s.name}, ${s.oldest != null ? '${dshow(s.oldest)} tarihli işlerimizden başlayarak ' : ''}toplam ${tl(s.kalan)} bakiyeniz bulunmaktadır. Müsait olduğunuzda ödemenizi rica ederiz. Teşekkürler.${f.isEmpty ? '' : '\n$f'}';
}

class TahsilatPage extends StatelessWidget {
  const TahsilatPage({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: S,
      builder: (c, _) {
        final l = S.cust.values.where((s) => s.kalan > 0.5).toList()
          ..sort((a, b) {
            final x = a.oldest, y = b.oldest;
            if (x == null && y == null) return 0;
            if (x == null) return 1;
            if (y == null) return -1;
            return x.compareTo(y);
          });
        return Scaffold(
          appBar: AppBar(title: Text('Tahsilat listesi (${l.length})')),
          body: ListView(padding: const EdgeInsets.all(12), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Text('Ödemesi en uzun süredir bekleyenler üstte. ${S.alacakGun} günü geçenler kırmızı işaretlenir. Yeşil WhatsApp düğmesi hazır hatırlatma mesajını açar. Telefon kayıtlı değilse kişiyi WhatsApp\'ta siz seçersiniz.', style: const TextStyle(color: grey, fontSize: 12.5)),
            ),
            if (l.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('Borçlu müşteri yok 🎉'))),
            for (final s in l)
              Box(
                border: (s.oldest != null && daysSince(s.oldest) >= S.alacakGun) ? red : null,
                onTap: () => push(c, MusteriDetay(s.name)),
                child: Row(children: [
                  Avatar(s.name),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('${tl(s.kalan)} · ${(S.telefon[norm(s.name)] ?? '').isEmpty ? 'telefon yok' : S.telefon[norm(s.name)]}', style: const TextStyle(fontSize: 12, color: grey)),
                      const SizedBox(height: 4),
                      agePill(s),
                      if ((S.soz[norm(s.name)] ?? '').length >= 10) Padding(padding: const EdgeInsets.only(top: 4), child: Pill('Söz: ${dshow(S.soz[norm(s.name)]!.substring(0, 10))}', gunKala(S.soz[norm(s.name)]!.substring(0, 10)) <= 0 ? red : blue)),
                    ]),
                  ),
                  IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                    onPressed: () => whatsapp(c, S.telefon[norm(s.name)], hatirlat(s)),
                    icon: const Icon(Icons.chat),
                  ),
                ]),
              ),
          ]),
        );
      });
}

// ============================ AYARLAR (FİRMA / LOGO) ============================
class AyarPage extends StatefulWidget {
  const AyarPage({super.key});
  @override
  State<AyarPage> createState() => _AyarState();
}

class _AyarState extends State<AyarPage> {
  late final firma = TextEditingController(text: S.ayar['firma'] ?? '');
  late final tel = TextEditingController(text: S.ayar['tel'] ?? '');
  late final gun = TextEditingController(text: '${S.alacakGun}');
  late final pin = TextEditingController(text: S.ayar['pin'] ?? '');
  late bool filigran = S.ayar['filigran'] != '0';
  late bool noLogo = S.ayar['logo_yok'] == '1';
  String? logo = S.ayar['logo'];

  @override
  Widget build(BuildContext context) {
    final custom = logo != null && File(fp(logo)).existsSync();
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Logo ve firma bilgileri PDF raporlarında görünür.', style: TextStyle(color: grey)),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () async {
            final f = await pickPhoto(context, 'logo');
            if (f != null) {
              setState(() {
                logo = f;
                noLogo = false;
              });
            }
          },
          child: Container(
            height: 150,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)),
            child: custom
                ? Padding(padding: const EdgeInsets.all(8), child: Image.file(File(fp(logo)), fit: BoxFit.contain))
                : (noLogo
                    ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add_photo_alternate_outlined, size: 40, color: Colors.white54), SizedBox(height: 6), Text('Logo ekle', style: TextStyle(color: Colors.white54))]))
                    : Padding(padding: const EdgeInsets.all(8), child: Image.asset('assets/logo.png', fit: BoxFit.contain))),
          ),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: () => setState(() { logo = null; noLogo = false; }), child: const Text('Varsayılan logo')),
          TextButton(onPressed: () => setState(() { logo = null; noLogo = true; }), child: const Text('Logoyu kaldır')),
        ]),
        const SizedBox(height: 4),
        TextField(controller: firma, decoration: const InputDecoration(labelText: 'Firma adı', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: tel, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Telefon', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: gun, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Ödeme hatırlatma süresi (gün)', helperText: 'Ödemesi bu kadar gündür beklenen müşteriler uyarılır (6 ay = 180)', border: OutlineInputBorder())),
        const SizedBox(height: 4),
        const Text('Görünüm', style: TextStyle(fontWeight: FontWeight.w700)),
        Wrap(spacing: 8, children: [
          for (final e in const [['sistem', 'Telefona göre'], ['acik', 'Açık'], ['koyu', 'Koyu']])
            ChoiceChip(
                label: Text(e[1]),
                selected: (S.ayar['tema'] ?? 'sistem') == e[0],
                onSelected: (_) {
                  S.ayar['tema'] = e[0];
                  S.commit();
                  setState(() {});
                }),
        ]),
        if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) ...[
          const SizedBox(height: 8),
          const Text('Pencere düzeni (bilgisayar)', style: TextStyle(fontWeight: FontWeight.w700)),
          Wrap(spacing: 8, children: [
            for (final e in const [['tam', 'Tam ekran'], ['orta', 'Geniş'], ['dar', 'Dar (telefon gibi)']])
              ChoiceChip(
                  label: Text(e[1]),
                  selected: (S.ayar['pencere'] ?? 'tam') == e[0],
                  onSelected: (_) {
                    S.ayar['pencere'] = e[0];
                    S.commit();
                    setState(() {});
                  }),
          ]),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Telefon bildirimleri'),
          subtitle: Text(Nat.full ? 'Çek vadesi, belge bitişi, ödeme sözü, bakım ve geciken alacak gününde bildirim gelir' : 'Bu sürümde (temel) yok', style: const TextStyle(fontSize: 12)),
          value: S.ayar['bildirim'] != '0' && Nat.full,
          onChanged: Nat.full
              ? (v) {
                  S.ayar['bildirim'] = v ? '1' : '0';
                  S.commit();
                  bildirimleriPlanla();
                  setState(() {});
                }
              : null,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Parmak izi ile aç'),
          subtitle: Text(Nat.full ? 'PIN koyduysanız parmak izi de kullanılır' : 'Bu sürümde (temel) yok', style: const TextStyle(fontSize: 12)),
          value: S.ayar['bio'] == '1' && Nat.full,
          onChanged: Nat.full
              ? (v) async {
                  if (v && !await Nat.bioAvailable()) {
                    if (mounted) msg(context, 'Telefonda kayıtlı parmak izi veya yüz tanıma yok.');
                    return;
                  }
                  S.ayar['bio'] = v ? '1' : '0';
                  S.commit();
                  if (mounted) setState(() {});
                }
              : null,
        ),
        const SizedBox(height: 8),
        TextField(controller: pin, keyboardType: TextInputType.number, obscureText: true, maxLength: 6, decoration: const InputDecoration(labelText: 'Uygulama kilidi PIN (4-6 rakam, boş = kilit yok)', helperText: 'PIN kayıt edilince bir kurtarma kodu verilir', border: OutlineInputBorder())),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Logoyu PDF arka planına silik (filigran) koy'), value: filigran, onChanged: (v) => setState(() => filigran = v)),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () async {
            final np = pin.text.trim();
            if (np.isNotEmpty && !RegExp(r'^\d{4,6}$').hasMatch(np)) {
              msg(context, 'PIN 4-6 haneli rakam olmalı.');
              return;
            }
            String? yeniKod;
            if (np.isEmpty) {
              S.ayar.remove('pin');
              S.ayar.remove('pin_kod');
            } else {
              S.ayar['pin'] = np;
              if ((S.ayar['pin_kod'] ?? '').isEmpty) {
                yeniKod = '${10000000 + Random().nextInt(89999999)}';
                S.ayar['pin_kod'] = yeniKod;
              }
            }
            S.ayar['firma'] = firma.text.trim();
            S.ayar['tel'] = tel.text.trim();
            S.ayar['filigran'] = filigran ? '1' : '0';
            S.ayar['gec_gun'] = '${(int.tryParse(gun.text.trim()) ?? 180).clamp(1, 3650)}';
            S.ayar['logo_yok'] = noLogo ? '1' : '0';
            if (logo == null) {
              S.ayar.remove('logo');
            } else {
              S.ayar['logo'] = logo!;
            }
            S.commit();
            if (yeniKod != null && context.mounted) {
              await showDialog(
                  context: context,
                  builder: (x) => AlertDialog(
                        title: const Text('Kurtarma kodunuz'),
                        content: Text('$yeniKod\n\nPIN\'i unutursanız bu kodla sıfırlarsınız. Bir yere not alın.'),
                        actions: [FilledButton(onPressed: () => Navigator.pop(x), child: const Text('Not aldım'))],
                      ));
            }
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Kaydet'),
        ),
      ]),
    );
  }
}

// ============================ BAKIM & SERVİS ============================
List<Fld> bakimFl() => [
      Fld('makina', 'Makina / araç', 'p', S.makinalar, true),
      const Fld('tur', 'Bakım türü', 'p', ['Yağ değişimi', 'Yağ filtresi', 'Hava filtresi', 'Yakıt filtresi', 'Hidrolik yağ', 'Gres / yağlama', 'Genel bakım', 'Lastik', 'Fren', 'Akü', 'Diğer']),
      const Fld('tarih', 'Bakım tarihi', 'd'),
      const Fld('saat', 'Bakım saati (örn. 14:30)'),
      const Fld('sayac', 'Motor saati / sayaç (ops.)', 'n'),
      const Fld('aralik', 'Sonraki bakım kaç ÇALIŞMA SAATİ sonra', 'n'),
      const Fld('gun', 'veya kaç GÜN sonra (ops.)', 'n'),
      const Fld('tutar', 'Maliyet ₺ (ops.)', 'n'),
      const Fld('aciklama', 'Açıklama', 'm'),
    ];

Widget bakimRec(BuildContext c, R r) {
  final ar = toD(r['aralik']), gn = toD(r['gun']);
  final bits = [
    dshow(r['tarih']) + ((r['saat'] ?? '').isEmpty ? '' : ' ${r['saat']}'),
    if ((r['sayac'] ?? '').isNotEmpty) 'motor ${r['sayac']} sa',
    if (ar > 0) 'her ${f2(ar)} sa',
    if (gn > 0) 'her ${f2(gn)} gün',
  ];
  return Box(
    pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    bottom: 6,
    onTap: () => editRec(c, S.bakim, 'bakım', bakimFl(), rec: r),
    child: Row(children: [
      Icon(Icons.build_circle, color: inkNavy, size: 22),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${r['tur'] ?? 'Bakım'} · ${r['makina'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(bits.join(' · ') + ((r['aciklama'] ?? '').isEmpty ? '' : '\n${r['aciklama']}'), style: const TextStyle(fontSize: 12, color: grey)),
        ]),
      ),
      if (toD(r['tutar']) > 0) Text(tl(toD(r['tutar'])), style: const TextStyle(fontWeight: FontWeight.w700)),
    ]),
  );
}

Widget bakimCard(BuildContext c, BStat b) {
  final col = b.durum == 'gec' ? red : (b.durum == 'yakin' ? orange : (b.durum == 'ok' ? green : grey));
  final lab = b.durum == 'gec' ? 'GECİKTİ' : (b.durum == 'yakin' ? 'YAKLAŞIYOR' : (b.durum == 'ok' ? 'Zamanı var' : 'Hatırlatma yok'));
  final r = b.r;
  final ks = b.kalanSaat, kg = b.kalanGun;
  final lines = <String>[
    'Son bakım: ${dshow(r['tarih'])}${(r['saat'] ?? '').isEmpty ? '' : ' ${r['saat']}'}${(r['sayac'] ?? '').isEmpty ? '' : ' · motor ${r['sayac']} sa'}',
    if (ks != null) 'Çalışma: ${f2(b.worked)} / ${f2(b.aralik)} sa · ${ks <= 0 ? '${f2(-ks)} sa geçti' : 'kalan ${f2(ks)} sa'}',
    if (kg != null) 'Süre: ${b.days} / ${f2(b.gun)} gün · ${kg <= 0 ? '${-kg} gün geçti' : 'kalan $kg gün'}',
    if (ks != null && toD(r['sayac']) > 0) 'Sonraki bakım: motor ${f2(toD(r['sayac']) + b.aralik)} sa',
  ];
  return Box(
    border: (b.durum == 'gec' || b.durum == 'yakin') ? col : null,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        MAvatar(b.makina),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(b.tur, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            Text(b.makina, style: const TextStyle(fontSize: 12, color: grey)),
          ]),
        ),
        Pill(lab, col),
      ]),
      if (b.durum != 'bilgi') ...[
        const SizedBox(height: 10),
        ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: b.ratio, color: col, backgroundColor: line, minHeight: 7)),
      ],
      const SizedBox(height: 8),
      for (final t in lines) Text(t, style: const TextStyle(fontSize: 12.5)),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () => editRec(c, S.bakim, 'bakım', bakimFl(), defaults: {'makina': b.makina, 'tur': b.tur, 'aralik': r['aralik'] ?? '', 'gun': r['gun'] ?? '', 'saat': nowHm()}),
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Bakımı yaptım – yenile'),
        ),
      ),
    ]),
  );
}

Widget bakimBanner() {
  final l = S.bakimDurum;
  final g = l.where((b) => b.durum == 'gec').length, y = l.where((b) => b.durum == 'yakin').length;
  if (g + y == 0) return const SizedBox();
  return Box(
    color: const Color(0xFFFFF1F0),
    border: red,
    onTap: () => goTab?.call(5),
    child: Row(children: [
      const Icon(Icons.build_circle, color: red),
      const SizedBox(width: 10),
      Expanded(child: Text('Bakım hatırlatması: $g gecikmiş, $y yaklaşan. Görmek için dokunun.', style: const TextStyle(fontWeight: FontWeight.w600))),
      const Icon(Icons.chevron_right, color: grey),
    ]),
  );
}

class BakimTab extends StatelessWidget {
  BakimTab({super.key});
  late final GCfg cfg = GCfg(
    month: false,
    title: 'Bakım & Servis',
    selLabel: 'Makina seç',
    items: () => S.bakim.toList(),
    keyOf: (r) => r['makina'] ?? '',
    allKeys: () => [...S.makinalar],
    sorts: [
      SortOpt('Son bakım', (a, b) => b.last.compareTo(a.last)),
      SortOpt('A–Z', (a, b) => norm(a.key).compareTo(norm(b.key))),
    ],
    card: (c, g) => Box(
      onTap: () => push(c, GroupDetailPage(cfg, g.key)),
      child: Row(children: [
        MAvatar(g.key),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(g.key, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            Text('${g.l.length} bakım kaydı · son: ${dshow(g.last)}', style: const TextStyle(fontSize: 12, color: grey)),
          ]),
        ),
        const Icon(Icons.chevron_right, color: grey),
      ]),
    ),
    rec: bakimRec,
    summary: (l) => Builder(builder: (c) {
      final names = {...l.map((r) => norm(r['makina'] ?? ''))};
      final bs = S.bakimDurum.where((b) => names.contains(norm(b.makina))).toList();
      if (bs.isEmpty) {
        return const Box(child: Text('Henüz bakım kaydı yok. + ile ilk bakımı ekleyin. "Kaç saat sonra" bilgisini girerseniz hatırlatma otomatik çalışır.', style: TextStyle(color: grey)));
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [secTitle('Hatırlatmalar'), for (final b in bs) bakimCard(c, b), secTitle('Bakım geçmişi')]);
    }),
    monthSum: (l) => tl(sum(l, (r) => toD(r['tutar']))),
    onAdd: (c, k) => editRec(c, S.bakim, 'bakım', bakimFl(), defaults: {'saat': nowHm(), if (k != null) 'makina': k}),
  );
  @override
  Widget build(BuildContext context) => GroupView(cfg);
}

// ============================ RENK / KATEGORİ / LOGO / UYARILAR ============================
const palette = [
  Color(0xFFE53935), Color(0xFF1E88E5), Color(0xFF43A047), Color(0xFFFB8C00), Color(0xFF8E24AA), Color(0xFF00ACC1), Color(0xFFD81B60), Color(0xFF6D4C41),
  Color(0xFF3949AB), Color(0xFF7CB342), Color(0xFFF4511E), Color(0xFF00897B), Color(0xFFFDD835), Color(0xFF546E7A), Color(0xFF5E35B1), Color(0xFFC0CA33),
];

int mIdx(String name) {
  final k = norm(name);
  final v = int.tryParse(S.renk[k] ?? '');
  if (v != null) return v % palette.length;
  final i = S.makinalar.indexWhere((x) => norm(x) == k);
  return (i < 0 ? name.runes.fold(0, (a, b) => a + b) : i) % palette.length;
}

Color mColor(String name) => palette[mIdx(name)];
Color katColor(String cat) => palette[cat.runes.fold(0, (a, b) => a + b) % palette.length];

int nextColorIdx() {
  final used = S.makinalar.map(mIdx).toSet();
  for (var i = 0; i < palette.length; i++) {
    if (!used.contains(i)) return i;
  }
  return 0;
}

Future<int?> pickColor(BuildContext c, int cur) => showDialog<int>(
    context: c,
    builder: (x) => AlertDialog(
          title: const Text('Renk seç'),
          content: Wrap(spacing: 12, runSpacing: 12, children: [
            for (var i = 0; i < palette.length; i++)
              GestureDetector(
                onTap: () => Navigator.pop(x, i),
                child: CircleAvatar(radius: 20, backgroundColor: palette[i], child: i == cur ? const Icon(Icons.check, color: Colors.white) : null),
              ),
          ]),
        ));

Future<String?> pickCat(BuildContext c, bool gider, String cur) {
  final list = gider ? S.gKatList : S.mKatList;
  return showDialog<String>(
      context: c,
      builder: (x) => AlertDialog(
            title: const Text('Kategori seç'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(shrinkWrap: true, children: [
                ListTile(leading: const Icon(Icons.block), title: const Text('Kategorisiz'), onTap: () => Navigator.pop(x, '')),
                for (final k in list) ListTile(leading: CircleAvatar(radius: 8, backgroundColor: katColor(k)), title: Text(k), selected: k == cur, onTap: () => Navigator.pop(x, k)),
                ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('Yeni kategori ekle…'),
                    onTap: () async {
                      final n = await askName(c, 'Yeni kategori');
                      if (n == null || n.isEmpty) return;
                      if (!list.any((e) => norm(e) == norm(n))) list.add(n);
                      if (x.mounted) Navigator.pop(x, n);
                    }),
              ]),
            ),
          ));
}

class KatPage extends StatelessWidget {
  final bool gider;
  const KatPage(this.gider, {super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: S,
      builder: (c, _) {
        final list = gider ? S.gKatList : S.mKatList;
        final assign = gider ? S.gKat : S.mKat;
        final unit = gider ? 'kalem' : 'müşteri';
        return Scaffold(
          appBar: AppBar(title: Text(gider ? 'Gider kategorileri' : 'Müşteri kategorileri')),
          body: list.isEmpty
              ? Center(
                  child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                          gider
                              ? 'Henüz kategori yok. + ile ekleyin (örn. Personel, Yakıt, Bakım).\nSonra gider kalemlerini bu kategorilere atarsınız.'
                              : 'Henüz kategori yok. + ile ekleyin (örn. Belediye, Şahıs, Firma).\nSonra müşteri sayfasından kategori atarsınız.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: grey))))
              : ListView(padding: const EdgeInsets.all(12), children: [
                  for (final k in list)
                    Box(
                      pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      bottom: 8,
                      child: Row(children: [
                        CircleAvatar(radius: 10, backgroundColor: katColor(k)),
                        const SizedBox(width: 12),
                        Expanded(child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
                        Text('${assign.values.where((v) => v == k).length} $unit', style: const TextStyle(color: grey, fontSize: 12)),
                        IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () async {
                              final n = await askName(c, 'Kategori adı', k);
                              if (n == null || n.isEmpty) return;
                              final i = list.indexOf(k);
                              if (i >= 0) list[i] = n;
                              for (final e in assign.entries.toList()) {
                                if (e.value == k) assign[e.key] = n;
                              }
                              S.commit();
                            }),
                        IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20, color: red),
                            onPressed: () {
                              list.remove(k);
                              assign.removeWhere((a, v) => v == k);
                              S.commit();
                            }),
                      ]),
                    ),
                ]),
          floatingActionButton: FloatingActionButton(
            onPressed: () async {
              final n = await askName(c, 'Yeni kategori');
              if (n != null && n.isNotEmpty && !list.any((x) => norm(x) == norm(n))) {
                list.add(n);
                S.commit();
              }
            },
            child: const Icon(Icons.add),
          ),
        );
      });
}

List<String> musteriSelOpts() => [
      for (final k in S.mKatList) 'Kategori: $k',
      if (S.mKatList.isNotEmpty) 'Kategori: Kategorisiz',
      ...([...S.musteriler]..sort((a, b) => norm(a).compareTo(norm(b)))),
    ];

List<String> giderSelOpts() => [
      for (final k in S.gKatList) 'Kategori: $k',
      if (S.gKatList.isNotEmpty) 'Kategori: Kategorisiz',
      ...({...S.giderler.map((e) => (e['kalem'] ?? '').trim())}.where((e) => e.isNotEmpty).toList()..sort((a, b) => norm(a).compareTo(norm(b)))),
    ];

Rep repMusteriSel(int sc, String? sel) => sel == null ? repMusteri(sc) : (sel.startsWith('Kategori: ') ? repMusteri(sc, sel.substring(10)) : repEkstre(sel));

// Logo: kırpılır; PDF başlığı için orijinal, arka plan için saydam/silik (filigran) sürüm üretilir
class LogoPack {
  final Uint8List orig, wm;
  final bool dark;
  LogoPack(this.orig, this.wm, this.dark);
}

Future<LogoPack?> loadLogo() async {
  try {
    Uint8List? b;
    final p = S.ayar['logo'];
    if (p != null && p.isNotEmpty && File(fp(p)).existsSync()) {
      b = await File(fp(p)).readAsBytes();
    } else if (S.ayar['logo_yok'] != '1') {
      final d = await rootBundle.load('assets/logo.png');
      b = d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes);
    }
    if (b == null) return null;
    final codec = await ui.instantiateImageCodec(b, targetWidth: 700);
    final im = (await codec.getNextFrame()).image;
    final w = im.width, h = im.height;
    final bd = await im.toByteData(format: ui.ImageByteFormat.rawRgba);
    var mode = 0; // 0: saydam zemin, 1: koyu zemin, 2: açık zemin
    var x0 = w, y0 = h, x1 = 0, y1 = 0;
    if (bd != null) {
      final a0 = bd.getUint8(3);
      final l0 = (bd.getUint8(0) + bd.getUint8(1) + bd.getUint8(2)) / 3;
      if (a0 > 200) mode = l0 < 70 ? 1 : (l0 > 185 ? 2 : 0);
      for (var y = 0; y < h; y += 2) {
        for (var x = 0; x < w; x += 2) {
          final o = (y * w + x) * 4;
          final a = bd.getUint8(o + 3);
          final l = (bd.getUint8(o) + bd.getUint8(o + 1) + bd.getUint8(o + 2)) / 3;
          final on = a > 40 && (mode == 0 || (mode == 1 ? l > 60 : l < 195));
          if (on) {
            if (x < x0) x0 = x;
            if (x > x1) x1 = x;
            if (y < y0) y0 = y;
            if (y > y1) y1 = y;
          }
        }
      }
    }
    if (x1 <= x0 || y1 <= y0) {
      x0 = 0;
      y0 = 0;
      x1 = w;
      y1 = h;
    }
    const pad = 6;
    final src = ui.Rect.fromLTRB((x0 - pad).clamp(0, w).toDouble(), (y0 - pad).clamp(0, h).toDouble(), (x1 + pad).clamp(0, w).toDouble(), (y1 + pad).clamp(0, h).toDouble());
    final cw = src.width.round(), ch = src.height.round();
    Future<Uint8List> render(ui.ColorFilter? f) async {
      final rec = ui.PictureRecorder();
      final cv = ui.Canvas(rec);
      cv.drawImageRect(im, src, ui.Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()), ui.Paint()..colorFilter = f);
      final out = await rec.endRecording().toImage(cw, ch);
      final png = await out.toByteData(format: ui.ImageByteFormat.png);
      return png!.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
    }

    final orig = await render(null);
    // Silik filigran: zemin tamamen şeffaf, logo çok açık gri tonunda (yazıları kapatmaz)
    final List<double> m = mode == 1
        ? [0, 0, 0, 0, 90, 0, 0, 0, 0, 90, 0, 0, 0, 0, 90, .04, .04, .04, 0, 0]
        : (mode == 2 ? [0, 0, 0, 0, 90, 0, 0, 0, 0, 90, 0, 0, 0, 0, 90, -.04, -.04, -.04, 0, 31] : [0, 0, 0, 0, 90, 0, 0, 0, 0, 90, 0, 0, 0, 0, 90, 0, 0, 0, .10, 0]);
    final wm = await render(ui.ColorFilter.matrix(m));
    return LogoPack(orig, wm, mode == 1);
  } catch (_) {
    return null;
  }
}

Widget alacakBanner() {
  final l = S.gecAlacak;
  if (l.isEmpty) return const SizedBox();
  final t = l.fold<double>(0.0, (a, s) => a + s.kalan);
  return Builder(
      builder: (c) => Box(
            color: const Color(0xFFFFF7ED),
            border: orange,
            onTap: () => push(c, const TahsilatPage()),
            child: Row(children: [
              const Icon(Icons.schedule, color: orange),
              const SizedBox(width: 10),
              Expanded(child: Text('${l.length} müşterinin ödemesi ${S.alacakGun} günü geçti (toplam ${tl(t)}). Tahsilat listesi için dokunun.', style: const TextStyle(fontWeight: FontWeight.w600))),
              const Icon(Icons.chevron_right, color: grey),
            ]),
          ));
}

Widget agingCard() {
  final a = S.aging;
  final tot = a.fold<double>(0.0, (x, y) => x + y);
  const labels = ['0–30 gün', '31–90 gün', '91–180 gün', '180+ gün'];
  const cols = [green, blue, orange, red];
  return Box(
    child: Column(children: [
      for (var i = 0; i < 4; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            SizedBox(width: 78, child: Text(labels[i], style: const TextStyle(fontSize: 12.5))),
            Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: tot == 0 ? 0 : a[i] / tot, color: cols[i], backgroundColor: line, minHeight: 10))),
            SizedBox(width: 96, child: Text(tl(a[i]), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        ),
    ]),
  );
}

// ============================ İŞ DETAYI / FOTOĞRAF / KÂRLILIK ============================
const asamalar = [
  ['once', 'İş öncesi', 'wb_twilight'],
  ['sirasinda', 'Çalışma sırasında', 'construction'],
  ['sonra', 'İş sonrası', 'task_alt'],
];

String zamanGoster(String? z) => (z != null && z.length >= 16) ? '${dshow(z.substring(0, 10))} ${z.substring(11, 16)}' : (z ?? '');

void fotoGoster(BuildContext c, R f) => showDialog(
    context: c,
    builder: (x) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: InteractiveViewer(
                child: Image.file(File(fp(f['yol'])), fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Padding(padding: EdgeInsets.all(40), child: Icon(Icons.broken_image, color: Colors.white54, size: 48))),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                Expanded(child: Text('${asamalar.firstWhere((a) => a[0] == f['asama'], orElse: () => ['', 'Fotoğraf', ''])[1]} · ${zamanGoster(f['zaman'])}', style: const TextStyle(color: Colors.white))),
                IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    onPressed: () {
                      try {
                        File(fp(f['yol'])).deleteSync();
                      } catch (_) {}
                      S.isFoto.remove(f);
                      S.commit();
                      Navigator.pop(x);
                    }),
                IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(x)),
              ]),
            ),
          ]),
        ));

Widget fotoBolum(BuildContext c, String jobId, String asama, String baslik, IconData ic) {
  final l = S.isFoto.where((f) => f['is'] == jobId && f['asama'] == asama).toList()..sort((a, b) => (a['zaman'] ?? '').compareTo(b['zaman'] ?? ''));
  return Box(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(ic, size: 20, color: inkNavy),
        const SizedBox(width: 8),
        Expanded(child: Text('$baslik (${l.length})', style: const TextStyle(fontWeight: FontWeight.w700))),
        TextButton.icon(
          icon: const Icon(Icons.add_a_photo, size: 18),
          label: const Text('Ekle'),
          onPressed: () async {
            final p = await pickPhoto(c, jobId);
            if (p == null) return;
            S.isFoto.add({'id': S.id(), 'is': jobId, 'asama': asama, 'yol': p, 'zaman': DateTime.now().toIso8601String().substring(0, 16)});
            S.commit();
          },
        ),
      ]),
      if (l.isEmpty)
        const Padding(padding: EdgeInsets.only(top: 2, bottom: 4), child: Text('Henüz fotoğraf yok', style: TextStyle(color: grey, fontSize: 12.5)))
      else
        SizedBox(
          height: 118,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final f in l)
              GestureDetector(
                onTap: () => fotoGoster(c, f),
                child: Container(
                  width: 118,
                  margin: const EdgeInsets.only(right: 8),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: line),
                  child: Stack(fit: StackFit.expand, children: [
                    Image.file(File(fp(f['yol'])), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: grey)),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(color: Colors.black54, padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3), child: Text(zamanGoster(f['zaman']), style: const TextStyle(color: Colors.white, fontSize: 10), textAlign: TextAlign.center)),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
    ]),
  );
}

Widget profitBox(JobProfit? p) {
  if (p == null) return const Box(child: Text('Bu kayıtta iş tutarı olmadığı için kârlılık hesaplanmadı.', style: TextStyle(color: grey)));
  Widget row(String a, double v, {bool minus = false, bool bold = false, Color? col}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500))),
          Text('${minus ? '– ' : ''}${tl(v)}', style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: col, fontSize: bold ? 16 : 14)),
        ]),
      );
  return Box(
    child: Column(children: [
      row('İş tutarı', p.gelir),
      row('Yakıt payı', p.yakit, minus: true),
      row('Bakım payı', p.bakim, minus: true),
      row('Genel gider payı', p.genel, minus: true),
      const Divider(),
      row('NET KAZANÇ', p.net, bold: true, col: signC(p.net)),
      Align(alignment: Alignment.centerRight, child: Pill('Kâr marjı %${p.marj.toStringAsFixed(1)}', signC(p.net) == Colors.black87 ? grey : signC(p.net))),
      const SizedBox(height: 6),
      const Text('Yakıt ve bakım payı, o makinanın o aydaki giderinin iş tutarına göre dağıtılmasıyla; genel gider payı, o ayki (mazot ödemesi hariç) giderlerin dağıtılmasıyla hesaplanır.', style: TextStyle(fontSize: 11.5, color: grey)),
    ]),
  );
}

class IsDetayPage extends StatelessWidget {
  final String id;
  const IsDetayPage(this.id, {super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: S,
      builder: (c, _) {
        final r = S.isler.firstWhere((x) => x['id'] == id, orElse: () => <String, String>{});
        if (r.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (c.mounted) Navigator.maybePop(c);
          });
          return const Scaffold();
        }
        final b = borc(r), a = toD(r['alinan']), k = b - a;
        return Scaffold(
          appBar: AppBar(title: Text(r['musteri'] ?? 'İş', overflow: TextOverflow.ellipsis), actions: [
            IconButton(
                icon: const Icon(Icons.copy_all_outlined),
                tooltip: 'Bu işi kopyala (yeni iş)',
                onPressed: () => editRec(c, S.isler, 'iş', isFl(), defaults: {for (final e in r.entries) if (!{'id', 'alinan', 'tarih', 'aciklama'}.contains(e.key)) e.key: e.value})),
            IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Düzenle / sil', onPressed: () => editRec(c, S.isler, 'iş', isFl(), rec: r)),
          ]),
          body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 40), children: [
            Box(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${r['makina'] ?? ''} · ${r['miktar'] ?? ''} × ${f2(toD(r['ucret']))} ₺', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 2),
                Text('${dshow(r['tarih'])}${(r['operator'] ?? '').isEmpty ? '' : ' · 👷 ${r['operator']}'}${isEk(r)}${(r['aciklama'] ?? '').isEmpty ? '' : '\n${r['aciklama']}'}', style: const TextStyle(color: grey)),
                const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [two(tl(b), 'Tutar'), two(tl(a), 'Alınan', ac: green), two(tl(k), 'Kalan', ac: k > 0.5 ? red : green)]),
              ]),
            ),
            if ((r['konum'] ?? '').isNotEmpty)
              Box(
                onTap: () => launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=${r['konum']}'), mode: LaunchMode.externalApplication),
                child: Row(children: [const Icon(Icons.map, color: blue), const SizedBox(width: 10), Expanded(child: Text('Haritada aç (${r['konum']})')), const Icon(Icons.open_in_new, size: 18, color: grey)]),
              ),
            secTitle('Bu iş bana gerçekten ne kazandırdı?'),
            profitBox(S.profit[id]),
            secTitle('Fotoğraflar (tarih-saat ile kaydedilir)'),
            fotoBolum(c, id, 'once', 'İş öncesi', Icons.wb_twilight),
            fotoBolum(c, id, 'sirasinda', 'Çalışma sırasında', Icons.construction),
            fotoBolum(c, id, 'sonra', 'İş sonrası', Icons.task_alt),
          ]),
        );
      });
}

class _Agg {
  double gelir = 0, yakit = 0, bakim = 0, genel = 0;
  int n = 0;
  double get net => gelir - yakit - bakim - genel;
  double get marj => gelir > 0 ? net / gelir * 100 : 0;
  void add(JobProfit p) {
    gelir += p.gelir;
    yakit += p.yakit;
    bakim += p.bakim;
    genel += p.genel;
    n++;
  }
}

class KarlilikPage extends StatefulWidget {
  const KarlilikPage({super.key});
  @override
  State<KarlilikPage> createState() => _KarState();
}

class _KarState extends State<KarlilikPage> {
  int seg = 0;
  bool enAz = false;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: Listenable.merge([S, ayF]),
      builder: (c, _) {
        final jobs = S.byMonth(S.isler, ayF.value).where((r) => S.profit[r['id'] ?? ''] != null).toList();
        final tot = _Agg();
        final byC = <String, _Agg>{}, byM = <String, _Agg>{}, names = <String, String>{};
        for (final r in jobs) {
          final p = S.profit[r['id']]!;
          tot.add(p);
          final ck = norm(r['musteri'] ?? ''), mk = norm(r['makina'] ?? '');
          names.putIfAbsent('c$ck', () => (r['musteri'] ?? '').trim().isEmpty ? 'Belirsiz' : r['musteri']!.trim());
          names.putIfAbsent('m$mk', () => (r['makina'] ?? '').trim().isEmpty ? 'Makinasız' : r['makina']!.trim());
          (byC[ck] ??= _Agg()).add(p);
          (byM[mk] ??= _Agg()).add(p);
        }
        final ent = (seg == 1 ? byC : byM).entries.toList()..sort((a, b) => enAz ? a.value.net.compareTo(b.value.net) : b.value.net.compareTo(a.value.net));
        final jl = [...jobs]..sort((a, b) => enAz ? S.profit[a['id']]!.net.compareTo(S.profit[b['id']]!.net) : S.profit[b['id']]!.net.compareTo(S.profit[a['id']]!.net));
        final zarar = jobs.where((r) => S.profit[r['id']]!.net < 0).length;
        return Scaffold(
          appBar: AppBar(title: const Text('Kârlılık analizi'), actions: const [AyDrop()]),
          body: ListView(padding: const EdgeInsets.all(12), children: [
            Box(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Gerçek net kazanç', style: TextStyle(color: grey)),
                FittedBox(fit: BoxFit.scaleDown, child: Text(tl(tot.net), style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: signC(tot.net)))),
                const SizedBox(height: 6),
                Wrap(spacing: 8, children: [Pill('Marj %${tot.marj.toStringAsFixed(1)}', signC(tot.net) == Colors.black87 ? grey : signC(tot.net)), Pill('${jobs.length} iş', blue), if (zarar > 0) Pill('$zarar iş zararda', red)]),
                const Divider(height: 22),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [two(tl(tot.gelir), 'İş tutarı'), two(tl(tot.yakit), '– Yakıt'), two(tl(tot.bakim), '– Bakım'), two(tl(tot.genel), '– Genel gider')]),
              ]),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 6),
              title: const Text('Genel giderleri iş payına kat'),
              subtitle: const Text('Kapalıysa sadece yakıt ve bakım düşülür', style: TextStyle(fontSize: 12)),
              value: S.ayar['genel_gider'] != '0',
              onChanged: (v) {
                S.ayar['genel_gider'] = v ? '1' : '0';
                S.commit();
              },
            ),
            Wrap(spacing: 8, children: [
              for (final e in const [['İşler', 0], ['Müşteriler', 1], ['Makinalar', 2]]) ChoiceChip(label: Text(e[0] as String), selected: seg == e[1], onSelected: (_) => setState(() => seg = e[1] as int)),
            ]),
            const SizedBox(height: 4),
            Wrap(spacing: 8, children: [
              ChoiceChip(label: const Text('En çok kazandıran'), selected: !enAz, onSelected: (_) => setState(() => enAz = false)),
              ChoiceChip(label: const Text('En az kazandıran / zarar'), selected: enAz, onSelected: (_) => setState(() => enAz = true)),
            ]),
            const SizedBox(height: 10),
            if (jobs.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('Bu dönemde tutarlı iş kaydı yok', style: TextStyle(color: grey)))),
            if (seg == 0)
              for (final r in jl)
                _karRow(c, '${r['musteri'] ?? ''}', '${dshow(r['tarih'])} · ${r['makina'] ?? ''} · ${r['miktar'] ?? ''}', S.profit[r['id']]!, () => push(c, IsDetayPage(r['id'] ?? '')))
            else
              for (final e in ent)
                _karAggRow(c, seg == 1 ? names['c${e.key}']! : names['m${e.key}']!, e.value, seg == 1),
          ]),
        );
      });

  Widget _karRow(BuildContext c, String t, String sub, JobProfit p, VoidCallback onTap) => Box(
        pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        bottom: 6,
        onTap: onTap,
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(sub, style: const TextStyle(fontSize: 12, color: grey)),
              Text('Tutar ${tl(p.gelir)} · yakıt ${tl(p.yakit)} · bakım ${tl(p.bakim)} · genel ${tl(p.genel)}', style: const TextStyle(fontSize: 11, color: grey)),
            ]),
          ),
          two(tl(p.net), '%${p.marj.toStringAsFixed(0)}', ac: signC(p.net), bc: signC(p.net)),
        ]),
      );

  Widget _karAggRow(BuildContext c, String name, _Agg a, bool musteri) => Box(
        pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        bottom: 6,
        onTap: musteri ? () => push(c, MusteriDetay(name)) : null,
        child: Row(children: [
          musteri ? Avatar(name) : MAvatar(name),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${a.n} iş · tutar ${tl(a.gelir)}', style: const TextStyle(fontSize: 12, color: grey)),
              Text('yakıt ${tl(a.yakit)} · bakım ${tl(a.bakim)} · genel ${tl(a.genel)}', style: const TextStyle(fontSize: 11, color: grey)),
            ]),
          ),
          two(tl(a.net), '%${a.marj.toStringAsFixed(0)}', ac: signC(a.net), bc: signC(a.net)),
        ]),
      );
}

// ---- WhatsApp metinleri ----
String waEkstre(String name, {int maxRows = 25}) {
  final s = S.cust[norm(name)] ?? CStat(name);
  final l = S.isler.where((r) => norm(r['musteri'] ?? '') == norm(name)).toList()..sort(cmpDate);
  double hrs = 0, trips = 0;
  for (final r in l) {
    final q = r['miktar'] ?? '';
    if (q.isEmpty) continue;
    if (q.contains(':')) {
      hrs += qty(q);
    } else {
      trips += qty(q);
    }
  }
  final f = S.ayar['firma'] ?? '';
  final cal = [if (hrs > 0) hm(hrs), if (trips > 0) '${f2(trips)} sefer'].join(' + ');
  final jobs = l.where((r) => borc(r) > 0).toList(), pays = l.where((r) => borc(r) == 0 && toD(r['alinan']) > 0).toList();
  final b = StringBuffer();
  if (f.isNotEmpty) b.writeln('*$f*');
  b.writeln('📋 *Hesap özeti – $name*');
  b.writeln('Tarih: ${dshow(todayIso())}');
  b.writeln();
  b.writeln('🕒 Toplam çalışma: ${cal.isEmpty ? '-' : cal}');
  b.writeln('💰 Toplam tutar: ${tl(s.borc)}');
  b.writeln('✅ Ödenen tutar: ${tl(s.alinan)}');
  b.writeln('⏳ Kalan tutar: *${tl(s.kalan)}*');
  if (s.oldest != null && s.kalan > 0.5) b.writeln('📅 En eski ödenmemiş iş: ${dshow(s.oldest)} (${daysSince(s.oldest)} gün)');
  if (jobs.isNotEmpty) {
    final cut = jobs.length > maxRows ? jobs.length - maxRows : 0;
    b.writeln();
    b.writeln('*İş detayı${cut > 0 ? ' (son $maxRows iş)' : ''}:*');
    for (final r in jobs.skip(cut)) {
      b.writeln('• ${dshow(r['tarih'])} ${r['makina'] ?? ''} ${r['miktar'] ?? ''} × ${f2(toD(r['ucret']))} = ${tl(borc(r))}${toD(r['alinan']) > 0 ? ' (ödenen ${tl(toD(r['alinan']))})' : ''}');
    }
  }
  if (pays.isNotEmpty) {
    b.writeln();
    b.writeln('*Tahsilatlar:*');
    for (final r in pays.skip(pays.length > 10 ? pays.length - 10 : 0)) {
      b.writeln('• ${dshow(r['tarih'])} ${tl(toD(r['alinan']))}');
    }
  }
  b.writeln();
  b.write('Teşekkür ederiz.');
  return b.toString();
}

String toWa(Rep r) {
  final f = S.ayar['firma'] ?? '';
  final b = StringBuffer();
  if (f.isNotEmpty) b.writeln('*$f*');
  b.writeln('📊 *${r.title}*');
  if (r.sub.isNotEmpty) b.writeln(r.sub);
  b.writeln();
  for (final row in r.rows) {
    b.writeln('• ${[for (var i = 0; i < row.length; i++) cellText(row[i], i, r)].where((e) => e.isNotEmpty).join(' | ')}');
  }
  if (r.foot.isNotEmpty) {
    b.writeln();
    b.writeln('*${[for (var i = 0; i < r.foot.length; i++) cellText(r.foot[i], i, r)].where((e) => e.isNotEmpty).join(' | ')}*');
  }
  return b.toString();
}

// ============================ PUANTAJ (PERSONEL DEVAM TAKİBİ) ============================
Color turColor(R? t) => palette[(int.tryParse(t?['renk'] ?? '') ?? 0) % palette.length];

class PAy {
  final Map<String, int> say = {};
  double calisan = 0, odenen = 0;
}

PAy pAy(String pid, int y, int m) {
  final p = '$y-${m.toString().padLeft(2, '0')}';
  final o = PAy();
  for (final r in S.puantaj) {
    if (r['pid'] != pid || !(r['tarih'] ?? '').startsWith(p)) continue;
    final t = S.turOf(r['tur']);
    if (t == null) continue;
    final id = t['id']!;
    o.say[id] = (o.say[id] ?? 0) + 1;
    final dv = toD(t['deger']);
    o.calisan += dv;
    if (t['ucretli'] == '1') o.odenen += dv > 0 ? dv : 1;
  }
  return o;
}

void setMark(String pid, String iso, String? turId, {bool commit = true}) {
  final old = S.markOf(pid, iso);
  if (turId == null) {
    if (old != null) S.puantaj.remove(old);
  } else if (old != null) {
    old['tur'] = turId;
  } else {
    S.puantaj.add({'id': S.id(), 'pid': pid, 'tarih': iso, 'tur': turId});
  }
  if (commit) S.commit();
}

Future<void> markDetail(BuildContext c, R p, String iso) async {
  final mk = S.markOf(p['id']!, iso);
  final res = await showForm(c, '${p['ad']} · ${dshow(iso)}', const [Fld('giris', 'Geliş saati (örn. 08:00)'), Fld('cikis', 'Çıkış saati (örn. 17:30)'), Fld('not', 'Not', 'm')], mk ?? {});
  if (res == null) return;
  if (mk == null) setMark(p['id']!, iso, 'c', commit: false);
  final m2 = S.markOf(p['id']!, iso);
  if (m2 != null) {
    m2['giris'] = res['giris'] ?? '';
    m2['cikis'] = res['cikis'] ?? '';
    m2['not'] = res['not'] ?? '';
  }
  S.commit();
}

Future<void> markSheet(BuildContext c, R p, String iso) {
  final cur = S.markOf(p['id']!, iso);
  final d = DateTime.parse(iso);
  return showModalBottomSheet(
      context: c,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (x) => SafeArea(
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('${p['ad']} · ${dshow(iso)} ${gunUzun[d.weekday - 1]}', style: Theme.of(c).textTheme.titleMedium)),
                for (final t in S.puanTur)
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(radius: 15, backgroundColor: turColor(t), child: Text(t['kisa'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w800))),
                    title: Text(t['ad'] ?? ''),
                    subtitle: Text('Gün değeri ${t['deger']} · ${t['ucretli'] == '1' ? 'ücretli' : 'ücretsiz'}', style: const TextStyle(fontSize: 11.5)),
                    trailing: cur?['tur'] == t['id'] ? const Icon(Icons.check_circle, color: green) : null,
                    onTap: () {
                      Navigator.pop(x);
                      setMark(p['id']!, iso, t['id']);
                    },
                  ),
                ListTile(
                    leading: const Icon(Icons.edit_note),
                    title: const Text('Geliş-çıkış saati / not ekle'),
                    onTap: () {
                      Navigator.pop(x);
                      markDetail(c, p, iso);
                    }),
                if (cur != null)
                  ListTile(
                      leading: const Icon(Icons.clear, color: red),
                      title: const Text('İşareti kaldır', style: TextStyle(color: red)),
                      onTap: () {
                        Navigator.pop(x);
                        setMark(p['id']!, iso, null);
                      }),
              ]),
            ),
          ));
}

Widget turPill(R? t) => t == null ? const Pill('İşaretlenmedi', grey) : Pill('${t['kisa']} · ${t['ad']}', turColor(t));

class PuantajTab extends StatefulWidget {
  const PuantajTab({super.key});
  @override
  State<PuantajTab> createState() => _PuanState();
}

class _PuanState extends State<PuantajTab> {
  DateTime day = DateTime.now();
  bool aylik = false, op = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: S,
      builder: (c, _) {
        final iso = dstr(day);
        final ay = aylik || op;
        return Scaffold(
          appBar: AppBar(title: const Text('Puantaj'), actions: [
            IconButton(icon: const Icon(Icons.tune), tooltip: 'Gün türleri (izin, rapor…)', onPressed: () => push(c, const TurPage())),
            IconButton(
                icon: const Icon(Icons.ios_share),
                tooltip: 'Rapor (PDF / Excel)',
                onPressed: () => op
                    ? exportSheet(c, 'Operatör raporu (${aylar[day.month]} ${day.year})', (s, sel) => repOperator(day.year, day.month, sel), selLabel: 'Operatör seç', selOptions: () => opNames())
                    : exportSheet(c, 'Puantaj raporu (${aylar[day.month]} ${day.year})', (s, sel) => repPuantaj(day.year, day.month, sel), selLabel: 'Personel seç', selOptions: () => [for (final p in S.personel) p['ad'] ?? ''])),
          ]),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Wrap(spacing: 8, children: [
                ChoiceChip(label: const Text('Günlük giriş'), selected: !aylik && !op, onSelected: (_) => setState(() { aylik = false; op = false; })),
                ChoiceChip(label: const Text('Aylık özet'), selected: aylik && !op, onSelected: (_) => setState(() { aylik = true; op = false; })),
                ChoiceChip(label: const Text('Operatör saatleri'), selected: op, onSelected: (_) => setState(() { op = true; aylik = false; })),
              ]),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => day = ay ? DateTime(day.year, day.month - 1, 1) : day.subtract(const Duration(days: 1)))),
              TextButton(
                onPressed: () async {
                  final d = await showDatePicker(context: c, initialDate: day, firstDate: DateTime(2020), lastDate: DateTime(2040));
                  if (d != null) setState(() => day = d);
                },
                child: Text(ay ? '${aylar[day.month]} ${day.year}' : '${dshow(iso)} ${gunUzun[day.weekday - 1]}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => day = ay ? DateTime(day.year, day.month + 1, 1) : day.add(const Duration(days: 1)))),
            ]),
            if (!ay && S.personel.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Icons.done_all),
                      label: const Text('İşaretlenmeyenleri "Çalıştı" yap'),
                      onPressed: () {
                        for (final p in S.personel) {
                          if (S.markOf(p['id']!, iso) == null) setMark(p['id']!, iso, 'c', commit: false);
                        }
                        S.commit();
                      },
                    ),
                  ),
                ]),
              ),
            Expanded(
              child: op
                  ? _opListe(c)
                  : (S.personel.isEmpty
                      ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Henüz personel yok. Sağ alttaki düğmeyle personel ekleyin, sonra her gün geliş-gidişlerini işaretleyin.', textAlign: TextAlign.center, style: TextStyle(color: grey))))
                      : ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 90), children: [for (final p in S.personel) aylik ? _aylikKart(c, p) : _gunKart(c, p, iso)])),
            ),
          ]),
          floatingActionButton: op
              ? null
              : FloatingActionButton(
                  onPressed: () => editRec(c, S.personel, 'personel', const [Fld('ad', 'Adı Soyadı'), Fld('gorev', 'Görevi (örn. operatör, şoför)'), Fld('tel', 'Telefon (ops.)'), Fld('ucret', 'Günlük ücret ₺ (hakediş için, ops.)', 'n')]),
                  child: const Icon(Icons.person_add),
                ),
        );
      });

  Widget _opListe(BuildContext c) {
    final l = opStats(day.year, day.month);
    if (l.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Operatör saatleri için iş eklerken "Operatör" alanını doldurun. Burada her operatörün aylık çalışma saati görünür.', textAlign: TextAlign.center, style: TextStyle(color: grey))));
    }
    return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 40), children: [
      for (final e in l)
        Box(
          onTap: () => push(c, OperatorPage(e.name, day.year, day.month)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Avatar(e.name),
              const SizedBox(width: 12),
              Expanded(child: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
              two(hm(e.hrs), '${e.n} iş${e.trips > 0 ? ' · ${f2(e.trips)} sefer' : ''}'),
            ]),
            if (e.mak.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 4, children: [for (final m in e.mak.entries) Pill('${m.key}: ${hm(m.value)}', mColor(m.key))]),
            ],
          ]),
        ),
    ]);
  }

  Widget _gunKart(BuildContext c, R p, String iso) {
    final mk = S.markOf(p['id']!, iso);
    final t = S.turOf(mk?['tur']);
    final saat = [if ((mk?['giris'] ?? '').isNotEmpty) 'Geliş ${mk!['giris']}', if ((mk?['cikis'] ?? '').isNotEmpty) 'Çıkış ${mk!['cikis']}', if ((mk?['not'] ?? '').isNotEmpty) mk!['not']!].join(' · ');
    return Box(
      onTap: () => markSheet(c, p, iso),
      child: Row(children: [
        Avatar(p['ad'] ?? ''),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p['ad'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            if ((p['gorev'] ?? '').isNotEmpty) Text(p['gorev']!, style: const TextStyle(fontSize: 12, color: grey)),
            if (saat.isNotEmpty) Text(saat, style: const TextStyle(fontSize: 12, color: grey)),
          ]),
        ),
        turPill(t),
      ]),
    );
  }

  Widget _aylikKart(BuildContext c, R p) {
    final a = pAy(p['id']!, day.year, day.month);
    final uc = toD(p['ucret']);
    return Box(
      onTap: () => push(c, PersonPage(p['id']!, day.year, day.month)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Avatar(p['ad'] ?? ''),
          const SizedBox(width: 12),
          Expanded(child: Text(p['ad'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
          two('${f2(a.calisan)} gün', uc > 0 ? 'hakediş ${tl(a.odenen * uc)}' : 'çalışılan'),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final t in S.puanTur)
            if ((a.say[t['id']] ?? 0) > 0) Pill('${t['kisa']} ${a.say[t['id']]}', turColor(t)),
          if (a.say.isEmpty) const Text('Bu ay işaret yok', style: TextStyle(fontSize: 12, color: grey)),
        ]),
      ]),
    );
  }
}

class PersonPage extends StatefulWidget {
  final String pid;
  final int y, m;
  const PersonPage(this.pid, this.y, this.m, {super.key});
  @override
  State<PersonPage> createState() => _PersonState();
}

class _PersonState extends State<PersonPage> {
  late DateTime ay = DateTime(widget.y, widget.m, 1);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: S,
      builder: (c, _) {
        final p = S.personel.firstWhere((x) => x['id'] == widget.pid, orElse: () => <String, String>{});
        if (p.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (c.mounted) Navigator.maybePop(c);
          });
          return const Scaffold();
        }
        final a = pAy(widget.pid, ay.year, ay.month);
        final uc = toD(p['ucret']);
        final oh = opStats(ay.year, ay.month).where((e) => norm(e.name) == norm(p['ad'] ?? '')).fold<double>(0.0, (x, e) => x + e.hrs);
        final apre = '${ay.year}-${ay.month.toString().padLeft(2, '0')}';
        final avl = S.avans.where((x) => x['pid'] == widget.pid && (x['tarih'] ?? '').startsWith(apre)).toList()..sort(cmpDate);
        final avT = sum(avl, (r) => toD(r['tutar']));
        final n = DateTime(ay.year, ay.month + 1, 0).day, lead = ay.weekday - 1;
        final cells = <Widget>[
          for (final g in gunAd) Center(child: Text(g, style: const TextStyle(fontSize: 11, color: grey, fontWeight: FontWeight.w700))),
          for (var i = 0; i < lead; i++) const SizedBox(),
          for (var d = 1; d <= n; d++) _gun(c, p, d),
        ];
        return Scaffold(
          appBar: AppBar(title: Text(p['ad'] ?? '', overflow: TextOverflow.ellipsis), actions: [
            IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Düzenle / sil', onPressed: () => editRec(c, S.personel, 'personel', const [Fld('ad', 'Adı Soyadı'), Fld('gorev', 'Görevi'), Fld('tel', 'Telefon'), Fld('ucret', 'Günlük ücret ₺', 'n')], rec: p)),
            IconButton(icon: const Icon(Icons.ios_share), onPressed: () => exportSheet(c, 'Puantaj - ${p['ad']}', (s, sel) => repPuantaj(ay.year, ay.month, p['ad']))),
          ]),
          body: ListView(padding: const EdgeInsets.all(12), children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => ay = DateTime(ay.year, ay.month - 1, 1))),
              Text('${aylar[ay.month]} ${ay.year}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => ay = DateTime(ay.year, ay.month + 1, 1))),
            ]),
            Box(
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [two('${f2(a.calisan)}', 'Çalışılan gün'), two('${f2(a.odenen)}', 'Ücretli gün'), if (uc > 0) two(tl(a.odenen * uc), 'Hakediş', ac: green), if (oh > 0) two(hm(oh), 'Operatör saati')]),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final t in S.puanTur)
                    if ((a.say[t['id']] ?? 0) > 0) Pill('${t['ad']} ${a.say[t['id']]}', turColor(t)),
                ]),
              ]),
            ),
            Box(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.payments_outlined, size: 18),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Avans (${tl(avT)})', style: const TextStyle(fontWeight: FontWeight.w700))),
                  TextButton.icon(icon: const Icon(Icons.add), label: const Text('Avans ekle'), onPressed: () => editRec(c, S.avans, 'avans', avansFl(), defaults: {'pid': widget.pid})),
                ]),
                if (uc > 0) Text('Hakediş ${tl(a.odenen * uc)} – avans ${tl(avT)} = ödenecek ${tl(a.odenen * uc - avT)}', style: const TextStyle(fontWeight: FontWeight.w700, color: green)),
                for (final x in avl)
                  ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text('${dshow(x['tarih'])} · ${tl(toD(x['tutar']))}'), subtitle: (x['not'] ?? '').isEmpty ? null : Text(x['not']!), onTap: () => editRec(c, S.avans, 'avans', avansFl(), rec: x)),
              ]),
            ),
            GridView.count(crossAxisCount: 7, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: .85, children: cells),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final t in S.puanTur) Row(mainAxisSize: MainAxisSize.min, children: [CircleAvatar(radius: 6, backgroundColor: turColor(t)), const SizedBox(width: 4), Text('${t['kisa']} ${t['ad']}', style: const TextStyle(fontSize: 11.5))]),
            ]),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.weekend),
              label: const Text('Ayın pazar günlerini "Hafta tatili" yap'),
              onPressed: () {
                for (var d = 1; d <= n; d++) {
                  final dt = DateTime(ay.year, ay.month, d);
                  final iso = dstr(dt);
                  if (dt.weekday == 7 && S.markOf(widget.pid, iso) == null) setMark(widget.pid, iso, 't', commit: false);
                }
                S.commit();
              },
            ),
          ]),
        );
      });

  Widget _gun(BuildContext c, R p, int d) {
    final iso = dstr(DateTime(ay.year, ay.month, d));
    final mk = S.markOf(p['id']!, iso);
    final t = S.turOf(mk?['tur']);
    final col = t == null ? null : turColor(t);
    return InkWell(
      onTap: () => markSheet(c, p, iso),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: col?.withAlpha(45) ?? cardC(c), border: Border.all(color: col ?? lineC(c)), borderRadius: BorderRadius.circular(10)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('$d', style: const TextStyle(fontSize: 11, color: grey)),
          Text(t?['kisa'] ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: col)),
        ]),
      ),
    );
  }
}

class TurPage extends StatelessWidget {
  const TurPage({super.key});

  List<Fld> get _fl => const [
        Fld('ad', 'Tür adı (örn. Düğün izni, Askerlik)'),
        Fld('kisa', 'Kısa kod (1-2 harf)'),
        Fld('deger', 'Çalışılmış gün değeri (1 = tam gün, 0,5 = yarım, 0 = çalışılmadı)', 'n'),
        Fld('ucretli', 'Gün ücreti ödenir mi?', 's', ['1=Evet, ücretli', '0=Hayır, ücretsiz']),
      ];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: S,
      builder: (c, _) => Scaffold(
            appBar: AppBar(title: const Text('Puantaj gün türleri')),
            body: ListView(padding: const EdgeInsets.all(12), children: [
              const Padding(padding: EdgeInsets.fromLTRB(4, 0, 4, 10), child: Text('İzin, rapor, hastane gibi türleri buradan düzenler, kendi türlerinizi ekleyebilirsiniz. Renk için daireye dokunun.', style: TextStyle(color: grey, fontSize: 12.5))),
              for (final t in S.puanTur)
                Box(
                  pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  bottom: 8,
                  child: Row(children: [
                    GestureDetector(
                      onTap: () async {
                        final i = await pickColor(c, int.tryParse(t['renk'] ?? '') ?? 0);
                        if (i != null) {
                          t['renk'] = '$i';
                          S.commit();
                        }
                      },
                      child: CircleAvatar(radius: 17, backgroundColor: turColor(t), child: Text(t['kisa'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w800))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t['ad'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('Gün değeri ${t['deger']} · ${t['ucretli'] == '1' ? 'ücretli' : 'ücretsiz'}', style: const TextStyle(fontSize: 12, color: grey)),
                      ]),
                    ),
                    IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () async {
                          final r = await showForm(c, 'Türü düzenle', _fl, t);
                          if (r == null) return;
                          t.addAll(r);
                          S.commit();
                        }),
                    IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20, color: red),
                        onPressed: () {
                          if (S.puantaj.any((m) => m['tur'] == t['id'])) {
                            msg(c, 'Bu türle işaretlenmiş günler var, silinemez. İsterseniz adını değiştirin.');
                            return;
                          }
                          S.puanTur.remove(t);
                          S.commit();
                        }),
                  ]),
                ),
            ]),
            floatingActionButton: FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Yeni tür'),
              onPressed: () async {
                final r = await showForm(c, 'Yeni gün türü', _fl, {'deger': '0', 'ucretli': '1'});
                if (r == null || (r['ad'] ?? '').isEmpty) return;
                if (!c.mounted) return;
                final i = await pickColor(c, S.puanTur.length % palette.length);
                final ad = r['ad']!;
                S.puanTur.add({
                  'id': 'u${DateTime.now().microsecondsSinceEpoch}',
                  'ad': ad,
                  'kisa': (r['kisa'] ?? '').isEmpty ? ad.substring(0, 1).toUpperCase() : r['kisa']!,
                  'renk': '${i ?? S.puanTur.length % palette.length}',
                  'deger': (r['deger'] ?? '').isEmpty ? '0' : r['deger']!,
                  'ucretli': r['ucretli'] ?? '1',
                });
                S.commit();
              },
            ),
          ));
}

Rep repPuantaj(int y, int m, [String? sel]) {
  final turler = S.puanTur;
  if (sel != null) {
    final p = S.personel.firstWhere((x) => norm(x['ad'] ?? '') == norm(sel), orElse: () => <String, String>{});
    final n = DateTime(y, m + 1, 0).day;
    final rows = <List<Object>>[];
    for (var d = 1; d <= n; d++) {
      final iso = dstr(DateTime(y, m, d));
      final mk = p.isEmpty ? null : S.markOf(p['id']!, iso);
      final t = S.turOf(mk?['tur']);
      rows.add([dshow(iso), gunAd[DateTime(y, m, d).weekday - 1], t?['ad'] ?? '-', mk?['giris'] ?? '', mk?['cikis'] ?? '', mk?['not'] ?? '']);
    }
    final a = p.isEmpty ? PAy() : pAy(p['id']!, y, m);
    final uc = toD(p['ucret']);
    return Rep('Puantaj - $sel', ['Tarih', 'Gün', 'Durum', 'Geliş', 'Çıkış', 'Not'], rows,
        sub: '${aylar[m]} $y · Çalışılan: ${f2(a.calisan)} gün · Ücretli gün: ${f2(a.odenen)}${uc > 0 ? ' · Hakediş: ${tl(a.odenen * uc, 'TL')}' : ''}');
  }
  final head = ['Personel', for (final t in turler) t['ad'] ?? '', 'Çalışılan gün', 'Hakediş', 'Avans', 'Net ödenecek'];
  final rows = <List<Object>>[];
  double top = 0, hak = 0, avt = 0;
  final apre = '$y-${m.toString().padLeft(2, '0')}';
  for (final p in S.personel) {
    final a = pAy(p['id']!, y, m);
    final h = a.odenen * toD(p['ucret']);
    final av = sum(S.avans.where((x) => x['pid'] == p['id'] && (x['tarih'] ?? '').startsWith(apre)), (r) => toD(r['tutar']));
    top += a.calisan;
    hak += h;
    avt += av;
    rows.add([p['ad'] ?? '', for (final t in turler) a.say[t['id']] ?? 0, a.calisan, h, av, h - av]);
  }
  return Rep('Puantaj Raporu', head, rows, sub: '${aylar[m]} $y · ${S.personel.length} personel', foot: ['TOPLAM', for (final t in turler) '', top, hak, avt, hak - avt], money: {head.length - 3, head.length - 2, head.length - 1});
}

// ============================ BENZER İSİM UYARISI ============================
int lev(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      final x = cur[j - 1] + 1, y = prev[j] + 1, z = prev[j - 1] + cost;
      cur[j] = x < y ? (x < z ? x : z) : (y < z ? y : z);
    }
    prev = cur;
  }
  return prev[b.length];
}

String _sortTok(String s) => (s.split(' ')..sort()).join(' ');

// Yazılana benzeyen kayıtlı isimleri bulur: başlangıç harfleri (Ah → Ahmet Öztürk), yazım hatası (Ahmt → Ahmet), kelime sırası
List<String> similar(String v, List<String> opts, {int max = 4}) {
  final q = norm(v);
  if (q.length < 2) return [];
  if (opts.any((o) => norm(o) == q)) return [];
  final scored = <MapEntry<String, int>>[];
  final seen = <String>{};
  for (final o in opts) {
    final n = norm(o);
    if (n.isEmpty || !seen.add(n)) continue;
    var sc = 99;
    final lim = q.length >= 6 ? 2 : (q.length >= 3 ? 1 : 0);
    if (n.startsWith(q) || n.split(' ').any((w) => w.startsWith(q))) {
      sc = 0;
    } else {
      final d = lev(n, q);
      if (d <= lim) {
        sc = d;
      } else {
        final d2 = lev(_sortTok(n), _sortTok(q));
        if (d2 <= lim) sc = d2;
      }
    }
    if (sc < 99) scored.add(MapEntry(o, sc));
  }
  scored.sort((a, b) => a.value != b.value ? a.value.compareTo(b.value) : a.key.length.compareTo(b.key.length));
  return scored.take(max).map((e) => e.key).toList();
}

// Kaydederken: benzer kayıt varsa "bunu mu demek istediniz?" diye sorar. null = vazgeç
Future<String?> confirmSimilar(BuildContext c, String v, List<String> opts, String what) async {
  final sg = similar(v, opts);
  if (sg.isEmpty) return v;
  final r = await showDialog<String>(
      context: c,
      builder: (x) => SimpleDialog(
            title: Text('$what: "$v" kayıtlı değil'),
            children: [
              const Padding(padding: EdgeInsets.fromLTRB(24, 0, 24, 8), child: Text('Şunlardan birini mi demek istediniz?')),
              for (final o in sg)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(x, o),
                  child: Row(children: [const Icon(Icons.check_circle_outline, color: green), const SizedBox(width: 8), Expanded(child: Text(o, style: const TextStyle(fontWeight: FontWeight.w700)))]),
                ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(x, ''),
                child: Row(children: [const Icon(Icons.add_circle_outline, color: blue), const SizedBox(width: 8), Expanded(child: Text('Hayır, yeni olarak ekle: "$v"'))]),
              ),
              SimpleDialogOption(onPressed: () => Navigator.pop(x), child: const Text('Vazgeç, düzelteyim', style: TextStyle(color: grey))),
            ],
          ));
  if (r == null) return null;
  return r.isEmpty ? v : r;
}

// ============================ KATEGORİ ADINA TAHSİLAT ============================
Future<void> katTahsilat(BuildContext c, String cat) async {
  final list = S.cust.values.where((s) => S.mCat(s.name) == cat && s.kalan > 0.5).toList();
  final tot = list.fold<double>(0.0, (a, s) => a + s.kalan);
  if (list.isEmpty) {
    msg(c, 'Bu kategoride borçlu müşteri yok.');
    return;
  }
  final res = await showForm(c, '$cat adına tahsilat (toplam borç ${tl(tot)})', const [Fld('tarih', 'Tarih', 'd'), Fld('alinan', 'Alınan tutar (₺)', 'n'), Fld('aciklama', 'Açıklama', 'm')], {'aciklama': 'Kategori tahsilatı: $cat'});
  if (res == null) return;
  final amt = toD(res['alinan']);
  if (amt <= 0) {
    if (c.mounted) msg(c, 'Tutar girilmedi.');
    return;
  }
  if (amt > tot + 0.5) {
    if (c.mounted) msg(c, 'Tutar kategorinin toplam borcunu (${tl(tot)}) aşıyor.');
    return;
  }
  final parts = <MapEntry<CStat, double>>[];
  var given = 0.0;
  for (var i = 0; i < list.length; i++) {
    final s = list[i];
    final share = i == list.length - 1 ? double.parse((amt - given).toStringAsFixed(2)) : double.parse((amt * s.kalan / tot).toStringAsFixed(2));
    given += share;
    if (share > 0) parts.add(MapEntry(s, share));
  }
  if (!c.mounted) return;
  final ok = await showDialog<bool>(
      context: c,
      builder: (x) => AlertDialog(
            title: Text('${tl(amt)} şöyle dağıtılacak'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(shrinkWrap: true, children: [
                const Text('Her müşterinin kalan borcuna oranla:', style: TextStyle(color: grey, fontSize: 12.5)),
                const SizedBox(height: 6),
                for (final p in parts)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [Expanded(child: Text(p.key.name)), Text(tl(p.value), style: const TextStyle(fontWeight: FontWeight.w700))]),
                  ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(x, false), child: const Text('Vazgeç')),
              FilledButton(onPressed: () => Navigator.pop(x, true), child: const Text('Onayla')),
            ],
          ));
  if (ok != true) return;
  for (final p in parts) {
    S.isler.add({'id': S.id(), 'musteri': p.key.name, 'tarih': (res['tarih'] ?? '').isEmpty ? todayIso() : res['tarih']!, 'alinan': f2(p.value), 'aciklama': '${res['aciklama'] ?? 'Kategori tahsilatı'} (toplam ${tl(amt)})'});
  }
  S.commit();
  if (c.mounted) msg(c, '${parts.length} müşteriye tahsilat işlendi.');
}

// ============================ OPERATÖR ============================
class OpStat {
  final String name;
  double hrs = 0, trips = 0, gelir = 0;
  int n = 0;
  final Map<String, double> mak = {};
  OpStat(this.name);
}

List<String> opNames() => ({...S.personel.map((p) => (p['ad'] ?? '').trim()), ...S.isler.map((r) => (r['operator'] ?? '').trim())}.where((e) => e.isNotEmpty).toList());

List<OpStat> opStats(int y, int m) {
  final p = '$y-${m.toString().padLeft(2, '0')}';
  final map = <String, OpStat>{};
  for (final r in S.isler) {
    final o = (r['operator'] ?? '').trim();
    if (o.isEmpty || !(r['tarih'] ?? '').startsWith(p)) continue;
    final st = map.putIfAbsent(norm(o), () => OpStat(o));
    final q = r['miktar'] ?? '';
    if (q.contains(':')) {
      st.hrs += qty(q);
      final mk = (r['makina'] ?? '-').trim();
      st.mak[mk] = (st.mak[mk] ?? 0) + qty(q);
    } else {
      st.trips += qty(q);
    }
    st.gelir += borc(r);
    st.n++;
  }
  for (final pr in S.personel) {
    final a = (pr['ad'] ?? '').trim();
    if (a.isNotEmpty) map.putIfAbsent(norm(a), () => OpStat(a));
  }
  return map.values.toList()..sort((a, b) => b.hrs.compareTo(a.hrs));
}

Rep repOperator(int y, int m, [String? sel]) {
  final p = '$y-${m.toString().padLeft(2, '0')}';
  final all = opStats(y, m).where((e) => sel == null || norm(e.name) == norm(sel)).toList();
  final jobs = S.isler.where((r) {
    final o = (r['operator'] ?? '').trim();
    return o.isNotEmpty && (r['tarih'] ?? '').startsWith(p) && (sel == null || norm(o) == norm(sel));
  }).toList()
    ..sort((a, b) {
      final c = norm(a['operator'] ?? '').compareTo(norm(b['operator'] ?? ''));
      return c != 0 ? c : cmpDate(a, b);
    });
  return Rep(
    sel == null ? 'Operatör Raporu' : 'Operatör - $sel',
    ['Operatör', 'İş', 'Çalışma saati', 'Sefer', 'İş tutarı'],
    [for (final e in all) [e.name, e.n, hm(e.hrs), e.trips, e.gelir]],
    sub: '${aylar[m]} $y · aylık çalışma saatleri',
    foot: ['TOPLAM', all.fold<int>(0, (a, e) => a + e.n), hm(all.fold<double>(0.0, (a, e) => a + e.hrs)), all.fold<double>(0.0, (a, e) => a + e.trips), all.fold<double>(0.0, (a, e) => a + e.gelir)],
    money: {4},
    extra: [
      Rep('Is detayi', ['Operatör', 'Tarih', 'Makina', 'Müşteri', 'Miktar', 'Tutar'], [for (final r in jobs) [r['operator'] ?? '', dshow(r['tarih']), r['makina'] ?? '', r['musteri'] ?? '', r['miktar'] ?? '', borc(r)]], sub: 'Operatörün yaptığı işler', money: {5}),
    ],
  );
}

class OperatorPage extends StatefulWidget {
  final String name;
  final int y, m;
  const OperatorPage(this.name, this.y, this.m, {super.key});
  @override
  State<OperatorPage> createState() => _OpState();
}

class _OpState extends State<OperatorPage> {
  late DateTime ay = DateTime(widget.y, widget.m, 1);
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: S,
      builder: (c, _) {
        final pre = '${ay.year}-${ay.month.toString().padLeft(2, '0')}';
        final st = opStats(ay.year, ay.month).firstWhere((e) => norm(e.name) == norm(widget.name), orElse: () => OpStat(widget.name));
        final jobs = S.isler.where((r) => norm(r['operator'] ?? '') == norm(widget.name) && (r['tarih'] ?? '').startsWith(pre)).toList()..sort((a, b) => cmpDate(b, a));
        return Scaffold(
          appBar: AppBar(title: Text(widget.name, overflow: TextOverflow.ellipsis), actions: [
            IconButton(icon: const Icon(Icons.ios_share), tooltip: 'Rapor', onPressed: () => exportSheet(c, 'Operatör - ${widget.name}', (a, b) => repOperator(ay.year, ay.month, widget.name))),
          ]),
          body: ListView(padding: const EdgeInsets.all(12), children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => ay = DateTime(ay.year, ay.month - 1, 1))),
              Text('${aylar[ay.month]} ${ay.year}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => ay = DateTime(ay.year, ay.month + 1, 1))),
            ]),
            Box(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Aylık çalışma saati', style: TextStyle(color: grey)),
                Text(hm(st.hrs), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [two('${st.n}', 'iş'), two(f2(st.trips), 'sefer'), two(tl(st.gelir), 'iş tutarı')]),
                if (st.mak.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 4, children: [for (final e in st.mak.entries) Pill('${e.key}: ${hm(e.value)}', blue)]),
                ],
              ]),
            ),
            if (jobs.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('Bu ay bu operatörle işlenmiş iş yok', style: TextStyle(color: grey)))),
            for (final r in jobs) jobRec(c, r),
          ]),
        );
      });
}

// ============================ YENİ ÖZELLİKLER (v10) ============================
int gunKala(String? iso) {
  final d = DateTime.tryParse(iso ?? '');
  if (d == null) return 9999;
  final n = DateTime.now();
  return DateTime(d.year, d.month, d.day).difference(DateTime(n.year, n.month, n.day)).inDays;
}

String isEk(R r) {
  final l = <String>[
    if ((r['santiye'] ?? '').isNotEmpty) '📍 ${r['santiye']}',
    if ((r['malzeme'] ?? '').isNotEmpty || (r['m3'] ?? '').isNotEmpty) '🧱 ${r['malzeme'] ?? ''} ${(r['m3'] ?? '').isEmpty ? '' : '${r['m3']} m³'}'.trim(),
    if ((r['irsaliye'] ?? '').isNotEmpty) '🧾 İrsaliye ${r['irsaliye']}',
  ];
  return l.isEmpty ? '' : '\n${l.join(' · ')}';
}

// ---------------- PIN kilidi ----------------
class LockGate extends StatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});
  @override
  State<LockGate> createState() => _LockState();
}

class _LockState extends State<LockGate> with WidgetsBindingObserver {
  bool locked = true;
  DateTime? bg;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState st) {
    if (st == AppLifecycleState.paused) bg = DateTime.now();
    if (st == AppLifecycleState.resumed && bg != null) {
      if (S.pin.isNotEmpty && DateTime.now().difference(bg!).inSeconds > 60) setState(() => locked = true);
      bg = null;
    }
  }

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        widget.child,
        if (S.pin.isNotEmpty && locked) Positioned.fill(child: PinScreen(onOk: () => setState(() => locked = false))),
      ]);
}

class PinScreen extends StatefulWidget {
  final VoidCallback onOk;
  const PinScreen({super.key, required this.onOk});
  @override
  State<PinScreen> createState() => _PinState();
}

class _PinState extends State<PinScreen> {
  String e = '';
  String? err;
  bool kurtar = false;

  bool get bioOn => Nat.full && S.ayar['bio'] == '1';

  @override
  void initState() {
    super.initState();
    if (bioOn) WidgetsBinding.instance.addPostFrameCallback((_) => _bio());
  }

  Future<void> _bio() async {
    if (!bioOn || kurtar) return;
    final ok = await Nat.bioAuth('Uygulamayı açmak için parmak izinizi okutun');
    if (ok && mounted) widget.onOk();
  }

  void _tap(String d) {
    final need = kurtar ? 8 : S.pin.length;
    if (e.length >= need) return;
    setState(() {
      e += d;
      err = null;
    });
    if (e.length == need) {
      if (kurtar) {
        if (e == (S.ayar['pin_kod'] ?? '#')) {
          S.ayar.remove('pin');
          S.ayar.remove('pin_kod');
          S.commit();
          widget.onOk();
          return;
        }
      } else if (e == S.pin) {
        widget.onOk();
        return;
      }
      HapticFeedback.heavyImpact();
      setState(() {
        e = '';
        err = kurtar ? 'Kod yanlış' : 'Yanlış PIN';
      });
    }
  }

  Widget _key(String k) => SizedBox(
        width: 88,
        height: 68,
        child: k.isEmpty
            ? null
            : InkWell(
                customBorder: const CircleBorder(),
                onTap: () {
                  if (k == '<') {
                    if (e.isNotEmpty) setState(() => e = e.substring(0, e.length - 1));
                  } else {
                    _tap(k);
                  }
                },
                child: Center(child: Text(k == '<' ? '⌫' : k, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w500))),
              ),
      );

  @override
  Widget build(BuildContext context) {
    final need = kurtar ? 8 : S.pin.length;
    return Scaffold(
      backgroundColor: navy,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.asset('assets/logo.png', width: 130)),
              const SizedBox(height: 18),
              Text(kurtar ? 'Kurtarma kodunu girin (8 hane)' : 'PIN girin', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < need; i++) Container(margin: const EdgeInsets.all(5), width: 13, height: 13, decoration: BoxDecoration(shape: BoxShape.circle, color: i < e.length ? amber : Colors.white24)),
              ]),
              SizedBox(height: 26, child: err == null ? null : Center(child: Text(err!, style: const TextStyle(color: Colors.redAccent)))),
              for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9'], ['', '0', '<']]) Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [for (final k in row) _key(k)]),
              if (bioOn && !kurtar) IconButton(icon: const Icon(Icons.fingerprint, color: amber, size: 44), onPressed: _bio),
              TextButton(
                onPressed: () => setState(() {
                  kurtar = !kurtar;
                  e = '';
                  err = null;
                }),
                child: Text(kurtar ? 'PIN ekranına dön' : 'PIN\'i unuttum', style: const TextStyle(color: Colors.white70)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------- Yedek hatırlatma ----------------
Future<void> yedekAl(BuildContext c) async {
  try {
    final p = await shareBytes(utf8.encode(S.export()), 'is_takip_yedek_${todayIso()}.json');
    S.ayar['son_yedek'] = todayIso();
    S.commit();
    if (p != null && c.mounted) msg(c, 'Yedek kaydedildi: $p');
  } catch (e) {
    if (c.mounted) msg(c, 'Hata: $e');
  }
}

Widget _ban(IconData ic, Color col, String t, VoidCallback onTap) => Box(
      color: col.withAlpha(22),
      border: col,
      onTap: onTap,
      child: Row(children: [
        Icon(ic, color: col),
        const SizedBox(width: 10),
        Expanded(child: Text(t, style: const TextStyle(fontWeight: FontWeight.w600))),
        const Icon(Icons.chevron_right, color: grey),
      ]),
    );

Widget uyariBannerlari() => Builder(builder: (c) {
      final cu = S.cekUyari, bu = S.belgeUyari, sg = S.sozGelen;
      final ys = S.ayar['son_yedek'];
      return Column(children: [
        if (cu.isNotEmpty) _ban(Icons.request_page, orange, '${cu.length} çek/senedin vadesi yaklaştı veya geçti (${tl(sum(cu, (r) => toD(r['tutar'])))}).', () => goTab?.call(8)),
        if (bu.isNotEmpty) _ban(Icons.badge, red, '${bu.length} makina belgesinin (muayene, sigorta…) süresi dolmak üzere veya doldu.', () => push(c, const BelgePage())),
        if (sg.isNotEmpty) _ban(Icons.event_note, blue, '${sg.length} müşterinin ödeme sözü günü geldi.', () => push(c, const TahsilatPage())),
        if (S.isler.isNotEmpty && (ys == null || ys.isEmpty || daysSince(ys) >= 7)) _ban(Icons.cloud_upload_outlined, grey, ys == null || ys.isEmpty ? 'Henüz yedek almadınız. Dokunup yedeği alın.' : 'Son yedekten ${daysSince(ys)} gün geçti. Dokunup yedeği alın.', () => yedekAl(c)),
      ]);
    });

// ---------------- Ödeme sözü ----------------
Future<void> sozDuzenle(BuildContext c, String name) async {
  final cur = S.soz[norm(name)];
  final init = <String, String>{
    if (cur != null && cur.length >= 10) 'tarih': cur.substring(0, 10),
    if (cur != null && cur.length > 11) 'not': cur.substring(11),
  };
  final r = await showForm(c, 'Ödeme sözü – $name', const [Fld('tarih', 'Ödeme sözü tarihi', 'd'), Fld('not', 'Not (örn. ay sonu çek verecek)')], init, canDelete: cur != null);
  if (r == null) return;
  if (r['_del'] == '1') {
    S.soz.remove(norm(name));
  } else {
    S.soz[norm(name)] = '${(r['tarih'] ?? '').isEmpty ? todayIso() : r['tarih']}|${r['not'] ?? ''}';
  }
  S.commit();
}

// ---------------- Çek & Senet ----------------
List<Fld> cekFl() => [
      const Fld('tur', 'Tür', 's', ['cek=Çek', 'senet=Senet']),
      Fld('musteri', 'Kimden (müşteri)', 'p', S.musteriler, true),
      const Fld('tutar', 'Tutar (₺)', 'n'),
      const Fld('vade', 'Vade tarihi', 'd'),
      const Fld('banka', 'Banka / keşideci (ops.)'),
      const Fld('no', 'Çek / senet no (ops.)'),
      const Fld('durum', 'Durum', 's', ['bekliyor=Bekliyor', 'tahsil=Tahsil edildi', 'karsiliksiz=Karşılıksız']),
      const Fld('aciklama', 'Açıklama', 'm'),
    ];

Future<void> cekTahsil(BuildContext c, R r) async {
  final ad = (r['musteri'] ?? '').trim();
  var hesaba = false;
  if (ad.isNotEmpty) {
    final ok = await showDialog<bool>(
        context: c,
        builder: (x) => AlertDialog(
              title: const Text('Tahsil edildi'),
              content: Text('${tl(toD(r['tutar']))} tutarı "$ad" hesabına tahsilat olarak da işlensin mi?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(x, false), child: const Text('Hayır, sadece durumu değiştir')),
                FilledButton(onPressed: () => Navigator.pop(x, true), child: const Text('Evet, işle')),
              ],
            ));
    if (ok == null) return;
    hesaba = ok;
  }
  r['durum'] = 'tahsil';
  if (hesaba) {
    final id = S.id();
    S.isler.add({'id': id, 'musteri': ad, 'tarih': todayIso(), 'alinan': f2(toD(r['tutar'])), 'aciklama': '${r['tur'] == 'senet' ? 'Senet' : 'Çek'} tahsili${(r['no'] ?? '').isEmpty ? '' : ' (no ${r['no']})'}'});
    r['tahsilat_id'] = id;
  }
  S.commit();
}

class CekTab extends StatefulWidget {
  const CekTab({super.key});
  @override
  State<CekTab> createState() => _CekState();
}

class _CekState extends State<CekTab> {
  String f = 'bekliyor';

  Widget _card(BuildContext c, R r) {
    final d = r['durum'] ?? 'bekliyor';
    final k = gunKala(r['vade']);
    final col = d == 'tahsil' ? green : (d == 'karsiliksiz' ? red : (k < 0 ? red : (k <= 7 ? orange : grey)));
    final lab = d == 'tahsil' ? 'Tahsil edildi' : (d == 'karsiliksiz' ? 'Karşılıksız' : (k < 0 ? '${-k} gün geçti' : (k == 0 ? 'Bugün' : '$k gün kaldı')));
    return Box(
      onTap: () => editRec(c, S.cek, 'çek/senet', cekFl(), rec: r),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(r['tur'] == 'senet' ? Icons.description_outlined : Icons.receipt_long, color: inkNavy),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${r['tur'] == 'senet' ? 'Senet' : 'Çek'} · ${r['musteri'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('Vade ${dshow(r['vade'])}${(r['banka'] ?? '').isEmpty ? '' : ' · ${r['banka']}'}${(r['no'] ?? '').isEmpty ? '' : ' · no ${r['no']}'}', style: const TextStyle(fontSize: 12, color: grey)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(tl(toD(r['tutar'])), style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 3), Pill(lab, col)]),
        ]),
        if (d == 'bekliyor')
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
                onPressed: () {
                  r['durum'] = 'karsiliksiz';
                  S.commit();
                },
                child: const Text('Karşılıksız', style: TextStyle(color: red))),
            FilledButton.tonal(onPressed: () => cekTahsil(c, r), child: const Text('Tahsil edildi')),
          ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: S,
      builder: (c, _) {
        final bek = S.cek.where((r) => (r['durum'] ?? 'bekliyor') == 'bekliyor').toList();
        final l = S.cek.where((r) => f == 'hepsi' || (r['durum'] ?? 'bekliyor') == f).toList()
          ..sort((a, b) => f == 'bekliyor' ? (a['vade'] ?? '').compareTo(b['vade'] ?? '') : (b['vade'] ?? '').compareTo(a['vade'] ?? ''));
        final yak = sum(bek.where((r) => gunKala(r['vade']) >= 0 && gunKala(r['vade']) <= 7), (r) => toD(r['tutar']));
        final gec = sum(bek.where((r) => gunKala(r['vade']) < 0), (r) => toD(r['tutar']));
        return Scaffold(
          appBar: AppBar(title: const Text('Çek & Senet')),
          body: Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 0), child: _sumRow([two(tl(sum(bek, (r) => toD(r['tutar']))), 'Bekleyen'), two(tl(yak), '7 gün içinde', ac: orange), two(tl(gec), 'Vadesi geçen', ac: red)])),
            SizedBox(
              height: 42,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                for (final e in const [['bekliyor', 'Bekleyen'], ['tahsil', 'Tahsil edilen'], ['karsiliksiz', 'Karşılıksız'], ['hepsi', 'Hepsi']])
                  Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(e[1]), selected: f == e[0], onSelected: (_) => setState(() => f = e[0]))),
              ]),
            ),
            Expanded(
              child: l.isEmpty
                  ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Kayıt yok. Sağ alttaki + ile çek veya senet ekleyin; vadesi yaklaşınca Özet\'te uyarı çıkar.', textAlign: TextAlign.center, style: TextStyle(color: grey))))
                  : ListView(padding: const EdgeInsets.fromLTRB(12, 6, 12, 90), children: [for (final r in l) _card(c, r)]),
            ),
          ]),
          floatingActionButton: FloatingActionButton(onPressed: () => editRec(c, S.cek, 'çek/senet', cekFl()), child: const Icon(Icons.add)),
        );
      });
}

// ---------------- Makina belgeleri ----------------
List<Fld> belgeFl() => [
      Fld('makina', 'Makina / araç', 'p', S.makinalar, true),
      const Fld('tur', 'Belge türü', 'p', ['Muayene', 'Trafik sigortası', 'Kasko', 'Ruhsat', 'Ehliyet', 'SRC belgesi', 'Psikoteknik', 'Diğer']),
      const Fld('bitis', 'Bitiş tarihi', 'd'),
      const Fld('aciklama', 'Not', 'm'),
    ];

class BelgePage extends StatelessWidget {
  const BelgePage({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: S,
      builder: (c, _) {
        final l = [...S.belge]..sort((a, b) => (a['bitis'] ?? '').compareTo(b['bitis'] ?? ''));
        return Scaffold(
          appBar: AppBar(title: const Text('Belgeler & sigorta')),
          body: l.isEmpty
              ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Muayene, trafik sigortası, kasko gibi belgelerin bitiş tarihlerini ekleyin. Süresi dolmadan Özet\'te uyarı çıkar.', textAlign: TextAlign.center, style: TextStyle(color: grey))))
              : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
                  for (final r in l)
                    Builder(builder: (c2) {
                      final k = gunKala(r['bitis']);
                      final col = k < 0 ? red : (k <= 30 ? orange : green);
                      return Box(
                        onTap: () => editRec(c, S.belge, 'belge', belgeFl(), rec: r),
                        child: Row(children: [
                          MAvatar(r['makina'] ?? ''),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(r['tur'] ?? 'Belge', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                              Text('${r['makina'] ?? ''} · bitiş ${dshow(r['bitis'])}', style: const TextStyle(fontSize: 12, color: grey)),
                            ]),
                          ),
                          Pill(k < 0 ? 'SÜRESİ DOLDU' : (k == 0 ? 'Bugün bitiyor' : '$k gün kaldı'), col),
                        ]),
                      );
                    }),
                ]),
          floatingActionButton: FloatingActionButton(onPressed: () => editRec(c, S.belge, 'belge', belgeFl()), child: const Icon(Icons.add)),
        );
      });
}

// ---------------- Tahsilat makbuzu ----------------
String _say(int n) {
  if (n == 0) return 'Sıfır';
  const bir = ['', 'Bir', 'İki', 'Üç', 'Dört', 'Beş', 'Altı', 'Yedi', 'Sekiz', 'Dokuz'];
  const on = ['', 'On', 'Yirmi', 'Otuz', 'Kırk', 'Elli', 'Altmış', 'Yetmiş', 'Seksen', 'Doksan'];
  final parts = <String>[];
  void yuz(int x) {
    final h = x ~/ 100, t = (x % 100) ~/ 10, b = x % 10;
    if (h > 0) parts.add(h == 1 ? 'Yüz' : '${bir[h]} Yüz');
    if (t > 0) parts.add(on[t]);
    if (b > 0) parts.add(bir[b]);
  }

  final milyar = n ~/ 1000000000, milyon = (n % 1000000000) ~/ 1000000, bin = (n % 1000000) ~/ 1000, kalan = n % 1000;
  if (milyar > 0) {
    yuz(milyar);
    parts.add('Milyar');
  }
  if (milyon > 0) {
    yuz(milyon);
    parts.add('Milyon');
  }
  if (bin > 0) {
    if (bin != 1) yuz(bin);
    parts.add('Bin');
  }
  if (kalan > 0) yuz(kalan);
  return parts.join(' ');
}

String yaziyla(double v) {
  final lira = v.floor();
  final kurus = ((v - lira) * 100).round();
  return '${_say(lira)} Türk Lirası${kurus > 0 ? ' ${_say(kurus)} Kuruş' : ''}';
}

Rep repMakbuz(R r) {
  final ad = (r['musteri'] ?? '').trim();
  final tut = toD(r['alinan']);
  final kalan = S.cust[norm(ad)]?.kalan ?? 0;
  final id = r['id'] ?? '';
  final no = 'MKB-${(r['tarih'] ?? '').replaceAll('-', '')}-${id.length > 4 ? id.substring(id.length - 4) : id}';
  return Rep(
    'TAHSİLAT MAKBUZU',
    ['Bilgi', 'Değer'],
    [
      ['Makbuz no', no],
      ['Tarih', dshow(r['tarih'])],
      ['Müşteri', ad],
      ['Tahsil edilen tutar', tl(tut, 'TL')],
      ['Yazıyla', yaziyla(tut)],
      ['Açıklama', (r['aciklama'] ?? '').isEmpty ? '-' : r['aciklama']!],
      ['Güncel kalan bakiye', tl(kalan, 'TL')],
    ],
    sub: 'Makbuz No: $no · ${dshow(r['tarih'])}',
    extra: [
      Rep('Imza', ['Teslim eden', 'Teslim alan'], [
        ['\n\n\n', '\n\n\n']
      ], sub: 'İmzalar'),
    ],
  );
}

String tahsilatMetni(R r) {
  final ad = (r['musteri'] ?? '').trim();
  final f = S.ayar['firma'] ?? '';
  return '✅ *Tahsilat alındı*${f.isEmpty ? '' : '\n$f'}\nMüşteri: $ad\nTarih: ${dshow(r['tarih'])}\nTutar: *${tl(toD(r['alinan']))}*\nKalan bakiye: ${tl(S.cust[norm(ad)]?.kalan ?? 0)}\nTeşekkür ederiz.';
}

void tahsilatMenu(BuildContext c, R r) => showModalBottomSheet(
    context: c,
    builder: (x) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: red),
                title: const Text('Makbuz oluştur (PDF)'),
                onTap: () async {
                  Navigator.pop(x);
                  try {
                    final id = r['id'] ?? '';
                    final pth = await shareBytes(await toPdf(repMakbuz(r)), 'makbuz_${todayIso()}_${id.length > 4 ? id.substring(id.length - 4) : id}.pdf');
                    if (pth != null && c.mounted) msg(c, 'İndirilenler klasörüne kaydedildi: $pth');
                  } catch (e) {
                    if (c.mounted) msg(c, 'Hata: $e');
                  }
                }),
            ListTile(
                leading: const Icon(Icons.chat, color: Color(0xFF25D366)),
                title: const Text('WhatsApp ile bildir'),
                onTap: () {
                  Navigator.pop(x);
                  whatsapp(c, S.telefon[norm(r['musteri'] ?? '')], tahsilatMetni(r));
                }),
            ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Düzenle / sil'),
                onTap: () {
                  Navigator.pop(x);
                  editRec(c, S.isler, 'tahsilat', tahsilatFl(), rec: r);
                }),
          ]),
        ));

// ---------------- Fiyat teklifi ----------------
Future<void> teklifHazirla(BuildContext c) async {
  final r = await showForm(
      c,
      'Fiyat teklifi hazırla',
      [
        Fld('musteri', 'Müşteri / Firma', 'p', S.musteriler, true),
        Fld('makina', 'Makina / hizmet', 'p', S.makinalar, true),
        const Fld('miktar', 'Tahmini süre: saat veya sefer sayısı', 'n'),
        const Fld('ucret', 'Birim fiyat (₺ / saat veya sefer)', 'n'),
        const Fld('ek_ad', 'Ek kalem (örn. nakliye, mobilizasyon)'),
        const Fld('ek_tutar', 'Ek kalem tutarı (₺)', 'n'),
        const Fld('gecerli', 'Teklif geçerlilik süresi (gün)', 'n'),
        const Fld('not', 'Notlar / şartlar', 'm'),
      ],
      {'gecerli': '15', 'not': 'Fiyatlara KDV dahil değildir.'});
  if (r == null) return;
  final q = toD(r['miktar']), u = toD(r['ucret']), ek = toD(r['ek_tutar']);
  final top = q * u + ek;
  final no = 'TKL-${todayIso().replaceAll('-', '')}-${nowHm().replaceAll(':', '')}';
  final gec = DateTime.now().add(Duration(days: toD(r['gecerli']).round()));
  final rows = <List<Object>>[
    [(r['makina'] ?? '').isEmpty ? 'Hizmet' : r['makina']!, f2(q), u, q * u],
    if ((r['ek_ad'] ?? '').isNotEmpty || ek > 0) [(r['ek_ad'] ?? '').isEmpty ? 'Ek kalem' : r['ek_ad']!, '1', ek, ek],
  ];
  final rep = Rep('FİYAT TEKLİFİ', ['Kalem', 'Miktar', 'Birim fiyat', 'Tutar'], rows,
      sub: 'Sayın ${(r['musteri'] ?? '').isEmpty ? 'Yetkili' : r['musteri']} · Teklif No: $no · Tarih: ${dshow(todayIso())} · Geçerlilik: ${dshow(dstr(gec))}',
      foot: ['TOPLAM', '', '', top],
      money: {2, 3},
      extra: [if ((r['not'] ?? '').isNotEmpty) Rep('Notlar', ['Notlar / şartlar'], [[r['not']!]], sub: 'Teklif şartları')]);
  try {
    final pth = await shareBytes(await toPdf(rep), 'teklif_${todayIso()}.pdf');
    if (pth != null && c.mounted) msg(c, 'İndirilenler klasörüne kaydedildi: $pth');
  } catch (e) {
    if (c.mounted) msg(c, 'Hata: $e');
  }
}

// ---------------- Aylık yönetim özeti ----------------
Map<String, double> _met(int m) {
  final js = S.byMonth(S.isler, m);
  final is_ = sum(js, borc), al = sum(js, (r) => toD(r['alinan'])), g = sum(S.byMonth(S.giderler, m), (r) => toD(r['tutar']));
  return {'İş tutarı': is_, 'Alınan': al, 'Gider': g, 'Net kâr (iş – gider)': is_ - g, 'Kasa (alınan – gider)': al - g};
}

Rep repAylik(int m) {
  final cur = _met(m);
  final prev = m > 1 ? _met(m - 1) : null;
  final rows = <List<Object>>[
    for (final e in cur.entries)
      [
        e.key,
        e.value,
        prev == null ? '-' : prev[e.key]!,
        (prev == null || prev[e.key] == 0) ? '-' : '%${((e.value - prev[e.key]!) / prev[e.key]!.abs() * 100).toStringAsFixed(0)}',
      ],
    ['Müşterilerde kalan (genel)', S.cust.values.fold<double>(0.0, (a, s) => a + s.kalan), '', ''],
    ['Mazot borcu (bilgi)', S.mazotBorcu, '', ''],
    ['Bekleyen çek / senet', sum(S.cek.where((r) => (r['durum'] ?? 'bekliyor') == 'bekliyor'), (r) => toD(r['tutar'])), '', ''],
    ['${S.alacakGun} günü geçen alacak', S.gecAlacak.fold<double>(0.0, (a, s) => a + s.kalan), '', ''],
  ];
  return Rep('Aylık Yönetim Özeti', ['Gösterge', aylar[m], m > 1 ? aylar[m - 1] : 'Önceki', 'Değişim'], rows,
      sub: '${aylar[m]} · ${dshow(todayIso())} tarihli özet', money: {1, 2}, extra: [repMakina(m), repMusteri(1), repGider(m)]);
}

List<Fld> avansFl() => const [Fld('tarih', 'Tarih', 'd'), Fld('tutar', 'Avans tutarı (₺)', 'n'), Fld('not', 'Not', 'm')];


// ============================ TELEFON BİLDİRİMLERİ ============================
Timer? _planT;
void planlaBildirim() {
  if (!Nat.full) return;
  _planT?.cancel();
  _planT = Timer(const Duration(seconds: 4), bildirimleriPlanla);
}

Future<void> bildirimleriPlanla() async {
  if (!Nat.full) return;
  if (S.ayar['bildirim'] == '0') {
    await Nat.reschedule([]);
    return;
  }
  final raw = <List<Object>>[];
  DateTime? gun(String? iso, {int back = 0}) {
    final d = DateTime.tryParse(iso ?? '');
    return d == null ? null : DateTime(d.year, d.month, d.day, 9).subtract(Duration(days: back));
  }

  void ekle(DateTime? t, String ti, String bo) {
    if (t != null) raw.add([t, ti, bo]);
  }

  for (final r in S.cek.where((r) => (r['durum'] ?? 'bekliyor') == 'bekliyor')) {
    final b = '${r['musteri'] ?? ''} · ${tl(toD(r['tutar']))}';
    final tur = r['tur'] == 'senet' ? 'senet' : 'çek';
    ekle(gun(r['vade'], back: 1), 'Yarın $tur vadesi', b);
    ekle(gun(r['vade']), 'Bugün $tur vadesi', b);
  }
  for (final r in S.belge) {
    final b = '${r['makina'] ?? ''} · ${r['tur'] ?? 'Belge'}';
    ekle(gun(r['bitis'], back: 30), 'Belge süresi 30 gün sonra doluyor', b);
    ekle(gun(r['bitis'], back: 7), 'Belge süresi 7 gün sonra doluyor', b);
    ekle(gun(r['bitis']), 'Belge süresi bugün doluyor', b);
  }
  S.soz.forEach((k, v) {
    final c = S.cust[k];
    if (c == null || c.kalan <= 0.5 || v.length < 10) return;
    ekle(gun(v.substring(0, 10)), 'Ödeme sözü günü', '${c.name} · ${tl(c.kalan)}');
  });
  for (final c in S.cust.values) {
    if (c.kalan > 0.5 && c.oldest != null) {
      ekle(gun(c.oldest, back: -S.alacakGun), '${S.alacakGun} günü doldu', '${c.name} · ${tl(c.kalan)} hâlâ ödenmedi');
    }
  }
  for (final b in S.bakimDurum) {
    if (b.gun > 0) ekle(gun(b.r['tarih'], back: -b.gun.round()), 'Bakım zamanı', '${b.makina} · ${b.tur}');
  }
  final now = DateTime.now();
  final fut = raw.where((e) => (e[0] as DateTime).isAfter(now)).toList()..sort((a, b) => (a[0] as DateTime).compareTo(b[0] as DateTime));
  final l = <NotifItem>[];
  for (var i = 0; i < fut.length && i < 60; i++) {
    l.add(NotifItem(1000 + i, fut[i][0] as DateTime, fut[i][1] as String, fut[i][2] as String));
  }
  await Nat.reschedule(l);
}
