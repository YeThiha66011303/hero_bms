// One BQStudio Data Memory parameter. The list itself (df_catalog.dart) is
// generated from TI's data flash table by the firmware repo's
// tools/gen_df_catalog.py.

/// One bit field of a hex register, as the TRM describes it.
class DfBit {
  const DfBit(this.name, this.lo, this.width, this.desc, this.values);

  final String name;

  /// Lowest bit and number of bits.
  final int lo, width;
  final String desc;

  /// TRM value lines, e.g. "1 = CHG FET remains on during sleep".
  final List<String> values;

  bool get reserved => name.startsWith('RSVD');
  int get mask => ((1 << width) - 1) << lo;

  int valueIn(int raw) => (raw >> lo) & ((1 << width) - 1);
  int withValue(int raw, int v) => (raw & ~mask) | ((v << lo) & mask);

  /// The TRM's text for value [v] of this field, if it lists one. Keys appear
  /// as "1", "0x7", "10" (binary) or "1,0" (one digit per bit, high first).
  String? meaning(int v) {
    final bin = v.toRadixString(2).padLeft(width, '0');
    final keys = {
      '$v',
      '0x${v.toRadixString(16)}',
      '0x${v.toRadixString(16).toUpperCase()}',
      bin,
      bin.split('').join(','),
    };
    for (final line in values) {
      final i = line.indexOf(' = ');
      if (i > 0 && keys.contains(line.substring(0, i))) return line.substring(i + 3);
    }
    return null;
  }
}

class DfParam {
  const DfParam(this.cls, this.sub, this.addr, this.name, this.type, this.min, this.max,
      this.defaultText, this.unit, this.writable, {this.bits = const []});

  /// Bit fields, high bit first; empty when the TRM does not break it down.
  final List<DfBit> bits;

  final String cls, sub, name, type, defaultText, unit;
  final int addr;

  /// TI's limits; null for strings.
  final int? min, max;

  /// False for the parameters the firmware refuses to write (calibration,
  /// fuse, PF enables, SMBus address, wiring, learned state, logs).
  final bool writable;

  bool get isString => type.startsWith('S');
  bool get isHex => type.startsWith('H');
  bool get isFloat => type == 'F4';
  bool get isSigned => type.startsWith('I');

  /// Stored in 0.1 K; shown in °C like BQStudio.
  bool get isKelvin => unit == '0.1 K';

  int get size => switch (type) {
        'U1' || 'I1' || 'H1' => 1,
        'U2' || 'I2' || 'H2' => 2,
        'U4' || 'I4' || 'H4' || 'F4' => 4,
        _ => int.parse(type.substring(1)) + 1, // Sn: length byte + n chars
      };

  String get displayUnit => isKelvin ? '°C' : (isHex ? '' : unit);

  /// Raw little-endian bytes to a number (not for strings).
  int decode(List<int> b) {
    var v = 0;
    for (var i = size - 1; i >= 0; i--) {
      v = (v << 8) | b[i];
    }
    if (isSigned && (v & (1 << (size * 8 - 1))) != 0) v -= 1 << (size * 8);
    return v;
  }

  String format(List<int> b) {
    if (isString) {
      final n = b[0].clamp(0, size - 1);
      return String.fromCharCodes(b.sublist(1, 1 + n).where((c) => c >= 0x20 && c < 0x7F));
    }
    final v = decode(b);
    if (isFloat) return '0x${v.toRadixString(16).toUpperCase().padLeft(8, '0')}';
    if (isHex) return '0x${v.toRadixString(16).toUpperCase().padLeft(size * 2, '0')}';
    if (isKelvin) return ((v - 2732) / 10).toStringAsFixed(1);
    return '$v';
  }

  /// What the user typed to a raw value, or null when it is not a number.
  int? parse(String text) {
    final t = text.trim();
    if (isHex) {
      final h = t.toLowerCase().startsWith('0x') ? t.substring(2) : t;
      return int.tryParse(h, radix: 16);
    }
    final v = num.tryParse(t);
    if (v == null) return null;
    if (isKelvin) return (v * 10).round() + 2732;
    return v == v.roundToDouble() ? v.toInt() : null;
  }

  String formatRaw(int raw) {
    if (isHex) return '0x${raw.toRadixString(16).toUpperCase().padLeft(size * 2, '0')}';
    if (isKelvin) return ((raw - 2732) / 10).toStringAsFixed(1);
    return '$raw';
  }

  /// Named fields that are set, e.g. "CB · CBR · CBS"; multi-bit fields as
  /// NAME=value. Empty when there are no bit definitions.
  String summary(int raw) => [
        for (final b in bits)
          if (!b.reserved && b.valueIn(raw) != 0) b.width == 1 ? b.name : '${b.name}=${b.valueIn(raw)}',
      ].join(' · ');

  String get limitText =>
      min == null || max == null ? '' : '${formatRaw(min!)} – ${formatRaw(max!)} $displayUnit'.trim();
}
