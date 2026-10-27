// lib/services/qris_service.dart
//
// QRIS Statis + Kode Unik — Pure Dart EMVCo TLV Parser & Builder.
// Menggunakan payload resmi QRIS "kopi sat" (NMID: ID1026516422080).

import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';

/// Payload QRIS Statis default proyek DigiQ (kopi sat - NMID: ID1026516422080)
const String kDefaultStaticQrisPayload =
    '00020101021126570011ID.DANA.WWW011893600915302435049402090243504940303UMI51440014ID.CO.QRIS.WWW0215ID10265164220800303UMI5204581353033605802ID5908kopi sat6015Kab. Nanggroe A6105245526304F95A';

// ─── Model Settings ───────────────────────────────────────────────────────────

class QrisSettings {
  final String staticPayload;
  final String merchantName;
  final String nmid;
  final int uniqueCodeMin;
  final int uniqueCodeMax;
  final int pendingTtlMinutes;

  const QrisSettings({
    required this.staticPayload,
    this.merchantName = 'kopi sat',
    this.nmid = 'ID1026516422080',
    required this.uniqueCodeMin,
    required this.uniqueCodeMax,
    required this.pendingTtlMinutes,
  });

  bool get hasPayload => staticPayload.isNotEmpty;

  factory QrisSettings.fromMap(Map<String, dynamic> m) {
    return QrisSettings(
      staticPayload: (m['qris_static_payload'] as String?)?.trim().isNotEmpty == true
          ? (m['qris_static_payload'] as String).trim()
          : kDefaultStaticQrisPayload,
      merchantName: (m['qris_merchant_name'] as String?) ?? 'kopi sat',
      nmid: (m['qris_nmid'] as String?) ?? 'ID1026516422080',
      uniqueCodeMin: int.tryParse(m['unique_code_min']?.toString() ?? '1') ?? 1,
      uniqueCodeMax: int.tryParse(m['unique_code_max']?.toString() ?? '300') ?? 300,
      pendingTtlMinutes: int.tryParse(m['pending_ttl_minutes']?.toString() ?? '15') ?? 15,
    );
  }
}

// ─── TLV Parser ──────────────────────────────────────────────────────────────

class TlvEntry {
  final String tag;
  final String value;
  const TlvEntry(this.tag, this.value);

  String encode() {
    final len = value.length.toString().padLeft(2, '0');
    return '$tag$len$value';
  }
}

List<TlvEntry> parseTlv(String qr) {
  final entries = <TlvEntry>[];
  int i = 0;
  while (i + 4 <= qr.length) {
    final tag = qr.substring(i, i + 2);
    final lenStr = qr.substring(i + 2, i + 4);
    final len = int.tryParse(lenStr);
    if (len == null || len < 0) break;
    if (i + 4 + len > qr.length) break;
    final value = qr.substring(i + 4, i + 4 + len);
    entries.add(TlvEntry(tag, value));
    i += 4 + len;
  }
  return entries;
}

String buildTlv(List<TlvEntry> entries) =>
    entries.map((e) => e.encode()).join();

// ─── CRC16 / CCITT-FALSE ─────────────────────────────────────────────────────
// Poly 0x1021, Init 0xFFFF, no reflect, XOR out 0x0000

int calculateCrc16(String data) {
  int crc = 0xFFFF;
  for (final ch in data.codeUnits) {
    crc ^= (ch << 8);
    for (int i = 0; i < 8; i++) {
      if ((crc & 0x8000) != 0) {
        crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
      } else {
        crc = (crc << 1) & 0xFFFF;
      }
    }
  }
  return crc;
}

String calculateCrc16Hex(String data) =>
    calculateCrc16(data).toRadixString(16).toUpperCase().padLeft(4, '0');

// ─── QrisService ─────────────────────────────────────────────────────────────

class QrisService {
  static SupabaseClient get _sb => SupabaseConfig.supabase;
  static QrisSettings? _cached;

  /// Validasi apakah checksum CRC16 pada payload QRIS EMVCo valid.
  static bool verifyCrc16(String payload) {
    final trimmed = payload.trim();
    if (trimmed.length < 8) return false;
    final crcTagIdx = trimmed.lastIndexOf('6304');
    if (crcTagIdx < 0 || crcTagIdx + 8 != trimmed.length) return false;

    final body = trimmed.substring(0, crcTagIdx + 4);
    final expectedCrc = calculateCrc16Hex(body);
    final actualCrc = trimmed.substring(crcTagIdx + 4).toUpperCase();
    return expectedCrc == actualCrc;
  }

  /// Alias untuk kompatibilitas kode lama.
  static bool validatePayload(String payload) => verifyCrc16(payload);

  /// Ekstrak metadata merchant seperti Merchant Name (Tag 59) dan NMID (Tag 51/26).
  static Map<String, String> extractMerchantInfo(String payload) {
    final info = <String, String>{
      'merchant_name': 'kopi sat',
      'nmid': 'ID1026516422080',
      'terminal': 'A01',
    };
    if (payload.isEmpty) return info;

    final entries = parseTlv(payload);
    for (final entry in entries) {
      if (entry.tag == '59') {
        info['merchant_name'] = entry.value;
      } else if (entry.tag == '60') {
        info['city'] = entry.value;
      } else if (entry.tag == '61') {
        info['postal_code'] = entry.value;
      } else if (entry.tag == '51') {
        // Parse sub-tags di Tag 51 (QRIS Merchant Account)
        final subEntries = parseTlv(entry.value);
        for (final sub in subEntries) {
          if (sub.tag == '02') {
            info['nmid'] = sub.value;
          }
        }
      } else if (entry.tag == '26' && (info['nmid'] == null || info['nmid'] == 'ID1026516422080')) {
        final subEntries = parseTlv(entry.value);
        for (final sub in subEntries) {
          if (sub.tag == '01') {
            info['acquirer_pan'] = sub.value;
          }
        }
      }
    }
    return info;
  }

  /// Bangun dynamic QRIS dari static payload EMVCo dengan menyuntikkan nominal totalAmount.
  /// Memenuhi standar EMVCo TLV:
  /// - Ubah Tag 01 menjadi dinamis ("12")
  /// - Sisipkan Tag 54 nominal tepat sebelum Tag 58 (atau Tag 63)
  /// - Hitung ulang Tag 63 CRC16-CCITT
  static String buildDynamicQris(String staticPayload, int totalAmount) {
    final source = staticPayload.trim().isNotEmpty
        ? staticPayload.trim()
        : kDefaultStaticQrisPayload;

    final entries = parseTlv(source);
    if (entries.isEmpty) return source;

    final output = <TlvEntry>[];

    for (final entry in entries) {
      if (entry.tag == '63') continue; // Hapus CRC lama
      if (entry.tag == '54') continue; // Hapus amount lama jika ada
      if (entry.tag == '01') {
        // Ubah: statis "11" → dinamis "12"
        output.add(const TlvEntry('01', '12'));
        continue;
      }
      output.add(entry);
    }

    // Sisipkan tag 54 (Transaction Amount) sebelum tag 58 (Country Code)
    final amountStr = totalAmount.toString();
    final tag54 = TlvEntry('54', amountStr);
    final insertIdx = output.indexWhere((e) => e.tag == '58');
    if (insertIdx >= 0) {
      output.insert(insertIdx, tag54);
    } else {
      output.add(tag54);
    }

    // Bangun string sebelum CRC, tambahkan tag 63 dengan length 04, lalu hitung CRC16
    final body = buildTlv(output);
    final toChecksum = '${body}6304';
    final crcHex = calculateCrc16Hex(toChecksum);
    return '$toChecksum$crcHex';
  }

  /// Alias fungsi untuk backwards compatibility
  static String? buildDynamicPayload({
    required String staticPayload,
    required double totalAmount,
  }) {
    if (staticPayload.isEmpty && kDefaultStaticQrisPayload.isEmpty) return null;
    return buildDynamicQris(
      staticPayload.isNotEmpty ? staticPayload : kDefaultStaticQrisPayload,
      totalAmount.toInt(),
    );
  }

  /// Muat pengaturan QRIS dari Supabase (cached).
  static Future<QrisSettings> loadSettings({bool forceRefresh = false}) async {
    if (_cached != null && !forceRefresh) return _cached!;
    try {
      final data = await _sb.rpc('get_qris_settings');
      _cached = QrisSettings.fromMap((data as Map<String, dynamic>?) ?? {});
    } catch (_) {
      _cached = const QrisSettings(
        staticPayload: kDefaultStaticQrisPayload,
        merchantName: 'kopi sat',
        nmid: 'ID1026516422080',
        uniqueCodeMin: 1,
        uniqueCodeMax: 300,
        pendingTtlMinutes: 15,
      );
    }
    return _cached!;
  }

  static void clearCache() => _cached = null;

  /// Format Rupiah, contoh: 10300 -> "Rp10.300", -100 -> "-Rp100"
  static String formatRupiah(num amount) {
    final isNegative = amount < 0;
    final absVal = amount.abs().toInt();
    final str = absVal.toString();
    final reversed = str.split('').reversed.toList();
    final buf = StringBuffer();
    for (int i = 0; i < reversed.length; i++) {
      if (i > 0 && i % 3 == 0) buf.write('.');
      buf.write(reversed[i]);
    }
    final formatted = buf.toString().split('').reversed.join('');
    return isNegative ? '-Rp$formatted' : 'Rp$formatted';
  }
}
