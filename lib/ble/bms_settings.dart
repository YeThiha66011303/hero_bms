// The data flash settings the firmware lets the app change.
//
// Mirrors kItems in main/df_settings.cpp (ids, limits, masks, partners). The
// firmware enforces all of it again; the copy here is so the app can explain a
// limit before sending, not instead of the firmware checking.

enum SettingKind { mv, ma, seconds, percent, tempK, bits }

class SettingDef {
  const SettingDef(
    this.id,
    this.group,
    this.name,
    this.kind,
    this.min,
    this.max, {
    this.mask = 0,
    this.bits = const [],
    this.partner = 0,
    this.order = 0,
    this.help,
  });

  final int id;
  final String group, name;
  final SettingKind kind;

  /// Raw limits, as stored on the gauge.
  final int min, max;

  /// Bit registers: bits the app may change, and their names (bit 0 first).
  final int mask;
  final List<String?> bits;

  /// Threshold/recovery pairing: this value must stay above (+1) or below (-1)
  /// the partner's current value.
  final int partner, order;
  final String? help;

  String get unit => switch (kind) {
        SettingKind.mv => 'mV',
        SettingKind.ma => 'mA',
        SettingKind.seconds => 's',
        SettingKind.percent => '%',
        SettingKind.tempK => '°C',
        SettingKind.bits => '',
      };

  /// Raw value to what BQStudio shows.
  String format(int raw) => switch (kind) {
        SettingKind.tempK => toDisplay(raw).toStringAsFixed(1),
        SettingKind.bits => '0x${raw.toRadixString(16).toUpperCase().padLeft(2, '0')}',
        _ => '$raw',
      };

  num toDisplay(int raw) => kind == SettingKind.tempK ? (raw - 2732) / 10 : raw;

  /// Display units back to raw, or null when [text] is not a number.
  int? parse(String text) {
    final v = num.tryParse(text.trim());
    if (v == null) return null;
    if (kind == SettingKind.tempK) return (v * 10).round() + 2732;
    return v is int ? v : (v == v.roundToDouble() ? v.toInt() : null);
  }

  String get limitText => '${format(min)} – ${format(max)} $unit'.trim();
}

const settingGroups = [
  'Cell balancing',
  'Cell undervoltage',
  'Cell overvoltage',
  'Charging',
  'Temperature protection',
  'Enabled protections',
];

// Temperature limits are stored in 0.1 K; 2732 = 0.0 °C.
int _deg(num c) => (c * 10).round() + 2732;

final settingDefs = <SettingDef>[
  // ---- Cell balancing -------------------------------------------------------
  const SettingDef(1, 'Cell balancing', 'Balancing Configuration', SettingKind.bits, 0, 0xFF,
      mask: 0x3D,
      bits: ['CB', 'CBM', 'CBR', 'CB_CHG_DOD0EW', 'CB_RLX_DOD0EW', 'CBS', null, null],
      help: 'CBM (external balancing) is locked: this board has no external balancing FETs.'),
  const SettingDef(2, 'Cell balancing', 'Min Start Balance Delta', SettingKind.mv, 1, 100,
      help: 'Balancing at rest is only recalculated when the cell spread is above this.'),
  const SettingDef(3, 'Cell balancing', 'Relax Balance Interval', SettingKind.seconds, 10, 36000,
      help: 'How often the gauge recalculates balancing time while resting.'),
  const SettingDef(4, 'Cell balancing', 'Min RSOC for Balancing', SettingKind.percent, 0, 100,
      help: 'Balancing at rest only runs above this state of charge.'),

  // ---- Cell undervoltage ----------------------------------------------------
  const SettingDef(10, 'Cell undervoltage', 'CUV Threshold', SettingKind.mv, 2000, 3000,
      partner: 11, order: -1, help: 'Discharge stops when a cell falls below this.'),
  const SettingDef(11, 'Cell undervoltage', 'CUV Recovery', SettingKind.mv, 2200, 3400,
      partner: 10, order: 1, help: 'Discharge is allowed again above this.'),
  const SettingDef(12, 'Cell undervoltage', 'CUV Delay', SettingKind.seconds, 1, 30),

  // ---- Cell overvoltage -----------------------------------------------------
  for (final (i, range) in _ranges.indexed)
    SettingDef(13 + i, 'Cell overvoltage', 'COV Threshold, $range', SettingKind.mv, 3500, 3800,
        partner: 19 + i, order: 1, help: 'Charging stops when a cell rises above this.'),
  const SettingDef(18, 'Cell overvoltage', 'COV Delay', SettingKind.seconds, 1, 30),
  for (final (i, range) in _ranges.indexed)
    SettingDef(19 + i, 'Cell overvoltage', 'COV Recovery, $range', SettingKind.mv, 3300, 3700,
        partner: 13 + i, order: -1, help: 'Charging is allowed again below this.'),

  // ---- Charging -------------------------------------------------------------
  for (final (i, range) in _ranges.indexed)
    SettingDef(30 + i, 'Charging', 'Charging Voltage, $range', SettingKind.mv, 3300, 3650,
        partner: 13 + i, order: -1,
        help: 'Per cell. Must stay below the COV threshold for the same range.'),
  const SettingDef(35, 'Charging', 'Charge Term Taper Current', SettingKind.ma, 50, 5000,
      help: 'Charge counts as complete once the current tapers below this.'),

  // ---- Temperature protection ---------------------------------------------
  SettingDef(40, 'Temperature protection', 'OTC Threshold', SettingKind.tempK, _deg(30), _deg(60),
      partner: 41, order: 1, help: 'Over-temperature in charge.'),
  SettingDef(41, 'Temperature protection', 'OTC Recovery', SettingKind.tempK, _deg(25), _deg(55),
      partner: 40, order: -1),
  SettingDef(42, 'Temperature protection', 'OTD Threshold', SettingKind.tempK, _deg(40), _deg(75),
      partner: 43, order: 1, help: 'Over-temperature in discharge.'),
  SettingDef(43, 'Temperature protection', 'OTD Recovery', SettingKind.tempK, _deg(30), _deg(70),
      partner: 42, order: -1),
  SettingDef(44, 'Temperature protection', 'UTC Threshold', SettingKind.tempK, _deg(-10), _deg(15),
      partner: 45, order: -1, help: 'Under-temperature in charge.'),
  SettingDef(45, 'Temperature protection', 'UTC Recovery', SettingKind.tempK, _deg(-5), _deg(20),
      partner: 44, order: 1),
  SettingDef(46, 'Temperature protection', 'UTD Threshold', SettingKind.tempK, _deg(-30), _deg(10),
      partner: 47, order: -1, help: 'Under-temperature in discharge.'),
  SettingDef(47, 'Temperature protection', 'UTD Recovery', SettingKind.tempK, _deg(-25), _deg(15),
      partner: 46, order: 1),

  // ---- Enabled protections (reserved bits are not shown and never change) --
  const SettingDef(50, 'Enabled protections', 'Enabled Protections A', SettingKind.bits, 0, 0xFF,
      mask: 0xBF, bits: ['CUV', 'COV', 'OCC1', 'OCC2', 'OCD1', 'OCD2', null, 'AOLDL']),
  const SettingDef(51, 'Enabled protections', 'Enabled Protections B', SettingKind.bits, 0, 0xFF,
      mask: 0x7B, bits: ['ASCC', 'ASCCL', null, 'ASCDL', 'OTC', 'OTD', 'CUVC', null]),
  const SettingDef(52, 'Enabled protections', 'Enabled Protections C', SettingKind.bits, 0, 0xFF,
      mask: 0xD7, bits: ['OTF', 'HWDF', 'PTO', null, 'CTO', null, 'OC', 'CHGC']),
  const SettingDef(53, 'Enabled protections', 'Enabled Protections D', SettingKind.bits, 0, 0xFF,
      mask: 0x3F, bits: ['CHGV', 'PCHGC', 'UTC', 'UTD', 'COVL', 'OCDL', null, null]),
];

const _ranges = ['Low Temp', 'Std Temp Low', 'Std Temp High', 'High Temp', 'Rec Temp'];

SettingDef? settingById(int id) {
  for (final d in settingDefs) {
    if (d.id == id) return d;
  }
  return null;
}

/// Plain-language meaning of the Balancing Configuration bits.
const balancingBitDescriptions = <String, String>{
  'CB': 'Cell balancing enabled',
  'CBM': 'External balancing FETs',
  'CBR': 'Balance while resting',
  'CB_CHG_DOD0EW': 'Error-weighted DOD0 for balancing time in charge',
  'CB_RLX_DOD0EW': 'Error-weighted DOD0 for balancing time at rest',
  'CBS': 'Balance in sleep',
};

/// Checks [raw] for [def] against its limits and its partner's current value.
/// Returns null when it is acceptable, otherwise the reason it is not.
String? validateSetting(SettingDef def, int raw, Map<int, int?> current) {
  if (raw < def.min || raw > def.max) return 'Allowed: ${def.limitText}';
  if (def.partner == 0) return null;
  final p = settingById(def.partner);
  final pv = current[def.partner];
  if (p == null || pv == null) return null;
  if (def.order > 0 && raw <= pv) {
    return 'Must be above ${p.name} (${p.format(pv)} ${p.unit})';
  }
  if (def.order < 0 && raw >= pv) {
    return 'Must be below ${p.name} (${p.format(pv)} ${p.unit})';
  }
  return null;
}
