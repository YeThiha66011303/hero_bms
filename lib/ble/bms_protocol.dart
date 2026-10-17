// Parsers for the BQ40Z80 firmware's BLE packets.
//
// Fields are read back in exactly the order main/ble_server.cpp writes them.
// docs/BLE_PROTOCOL.md in the firmware repo is the reference; if you add a
// field there, add it here in the same position and bump the version.
import 'dart:typed_data';

class ProtocolException implements Exception {
  ProtocolException(this.message);
  final String message;
  @override
  String toString() => 'ProtocolException: $message';
}

/// Sequential little-endian reader.
class _Reader {
  _Reader(List<int> bytes)
      : _data = ByteData.sublistView(Uint8List.fromList(bytes));

  final ByteData _data;
  int _pos = 0;

  int get length => _data.lengthInBytes;
  int get position => _pos;

  void _need(int n) {
    if (_pos + n > length) {
      throw ProtocolException('packet too short: need ${_pos + n}, have $length');
    }
  }

  int u8() { _need(1); return _data.getUint8(_pos++); }
  int i8() { _need(1); return _data.getInt8(_pos++); }
  int u16() { _need(2); final v = _data.getUint16(_pos, Endian.little); _pos += 2; return v; }
  int i16() { _need(2); final v = _data.getInt16(_pos, Endian.little); _pos += 2; return v; }
  int u32() { _need(4); final v = _data.getUint32(_pos, Endian.little); _pos += 4; return v; }
  int i32() { _need(4); final v = _data.getInt32(_pos, Endian.little); _pos += 4; return v; }

  List<int> i16s(int n) => List.generate(n, (_) => i16());
  List<int> u8s(int n) => List.generate(n, (_) => u8());

  String str() {
    final n = u8();
    _need(n);
    final s = String.fromCharCodes(
        Uint8List.sublistView(_data, _pos, _pos + n).where((c) => c >= 0x20 && c < 0x7F));
    _pos += n;
    return s;
  }
}

void _checkVersion(int got, int want, String what) {
  if (got != want) {
    throw ProtocolException('$what version $got, app understands $want -- update the app');
  }
}

/// Raw 0.1 K to degrees C. An unconnected thermistor reads 0; that becomes null.
double? dKToC(int dK) => dK <= 0 ? null : dK / 10.0 - 273.15;

// =============================================================================
// LIVE -- fast tier, notified once a second (152 bytes, version 1)
// =============================================================================
class LiveData {
  LiveData._(_Reader r) {
    _checkVersion(r.u8(), 1, 'LIVE');
    final flags = r.u8();
    online = flags & 0x01 != 0;
    staticValid = flags & 0x02 != 0;
    resetSafe = flags & 0x04 != 0;
    cellCount = r.u8().clamp(1, 7);
    rsoc = r.u8();
    asoc = r.u8();
    maxError = r.u8();

    uptimeS = r.u32();
    pollCount = r.u32();
    errorCount = r.u32();

    voltageMv = r.u16();
    currentMa = r.i16();
    avgCurrentMa = r.i16();
    tempDk = r.u16();
    remainingMah = r.u16();
    fullChargeMah = r.u16();
    chargingCurrentMa = r.u16();
    chargingVoltageMv = r.u16();
    batteryStatus = r.u16();

    batMv = r.i16();
    packMv = r.i16();
    allCellPowerCw = r.i16();
    avgPowerCw = r.i16();

    cellMv = r.i16s(7);
    cellMa = r.i16s(7);
    cellPowerCw = r.i16s(7);
    tempsDk = r.i16s(7);

    operationStatus = r.u32();
    safetyStatus = r.u32();
    safetyAlert = r.u32();
    chargingStatus = r.u32();
    gaugingStatus = r.u32();
    mfgStatus = r.u16();
    pfStatus = r.u32();
    pfAlert = r.u32();

    cycleCount = r.u16();
    sohPct = r.u16();
    runTimeToEmptyMin = r.u16();
    avgTimeToEmptyMin = r.u16();
    avgTimeToFullMin = r.u16();

    resetCount = r.u32();
    resetLastAtS = r.u32();
    resetLastErr = r.i32();
  }

  factory LiveData.parse(List<int> bytes) => LiveData._(_Reader(bytes));

  static const int packetLength = 152;

  late final bool online, staticValid, resetSafe;
  late final int cellCount, rsoc, asoc, maxError;
  late final int uptimeS, pollCount, errorCount;
  late final int voltageMv, currentMa, avgCurrentMa, tempDk;
  late final int remainingMah, fullChargeMah;
  late final int chargingCurrentMa, chargingVoltageMv, batteryStatus;
  late final int batMv, packMv, allCellPowerCw, avgPowerCw;
  late final List<int> cellMv, cellMa, cellPowerCw;

  /// Int, TS1, TS2, TS3, TS4, Cell, FET -- raw 0.1 K.
  late final List<int> tempsDk;
  late final int operationStatus, safetyStatus, safetyAlert;
  late final int chargingStatus, gaugingStatus, mfgStatus, pfStatus, pfAlert;
  late final int cycleCount, sohPct;
  late final int runTimeToEmptyMin, avgTimeToEmptyMin, avgTimeToFullMin;
  late final int resetCount, resetLastAtS, resetLastErr;

  // ---- derived ------------------------------------------------------------
  List<int> get cells => cellMv.sublist(0, cellCount);
  int get cellMin => cells.reduce((a, b) => a < b ? a : b);
  int get cellMax => cells.reduce((a, b) => a > b ? a : b);
  int get cellSpread => cellMax - cellMin;
  int get cellMinIndex => cells.indexOf(cellMin);
  int get cellMaxIndex => cells.indexOf(cellMax);

  double get voltage => voltageMv / 1000.0;
  double get current => currentMa / 1000.0;
  double get powerW => voltage * current;
  double? get temperatureC => dKToC(tempDk);

  bool _op(int bit) => (operationStatus >> bit) & 1 == 1;
  bool get dsgFet => _op(1);
  bool get chgFet => _op(2);
  bool get pchgFet => _op(3);
  bool get pdsgFet => _op(4);
  bool get permanentFailure => _op(12);
  bool get dischargeDisabled => _op(13);
  bool get chargeDisabled => _op(14);
  bool get balancing => _op(28);

  /// 0 reserved, 1 full access, 2 unsealed, 3 sealed.
  int get securityMode => (operationStatus >> 8) & 0x3;

  bool get fetEnabled => (mfgStatus >> 4) & 1 == 1;
  bool get gaugeEnabled => (mfgStatus >> 3) & 1 == 1;

  /// Charging is detected when the Gauging Status DSG bit is clear.
  bool get chargeDetected => (gaugingStatus >> 6) & 1 == 0;
  bool get relaxOcvTaken => (gaugingStatus >> 8) & 1 == 1;

  String get gaugingState {
    if (chargeDetected) return 'Charging';
    if (currentMa.abs() <= 50) return relaxOcvTaken ? 'Relax (OCV taken)' : 'Relax';
    return 'Discharging';
  }
}

// =============================================================================
// INFO -- static identity, read once (version 1, variable length)
// =============================================================================
class InfoData {
  InfoData._(_Reader r) {
    _checkVersion(r.u8(), 1, 'INFO');
    final flags = r.u8();
    valid = flags & 0x01 != 0;
    protCValid = flags & 0x02 != 0;
    mfgStatusInitValid = flags & 0x04 != 0;
    cellCount = r.u8();
    enabledProtectionsC = r.u8();
    chemId = r.u16();
    deviceType = r.u16();
    serialNumber = r.u16();
    designCapacityMah = r.u16();
    designVoltageMv = r.u16();
    manufactureDate = r.u16();
    mfgStatusInit = r.u16();
    manufacturer = r.str();
    deviceName = r.str();
    chemistry = r.str();
  }

  factory InfoData.parse(List<int> bytes) => InfoData._(_Reader(bytes));

  late final bool valid, protCValid, mfgStatusInitValid;
  late final int cellCount, enabledProtectionsC, chemId, deviceType, serialNumber;
  late final int designCapacityMah, designVoltageMv, manufactureDate, mfgStatusInit;
  late final String manufacturer, deviceName, chemistry;

  /// SBS date packing: (year-1980)<<9 | month<<5 | day.
  String get manufactureDateText {
    if (manufactureDate == 0) return '-';
    final y = 1980 + (manufactureDate >> 9);
    final m = (manufactureDate >> 5) & 0xF;
    final d = manufactureDate & 0x1F;
    return '$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
  }

  bool get isLfpChemId =>
      (chemId & 0xFF00) == 0x0400 || (chemId & 0xF000) == 0x4000;
}

// =============================================================================
// DETAIL -- slow tier, read on demand (296 bytes, version 1)
// =============================================================================
class DetailData {
  DetailData._(_Reader r) {
    _checkVersion(r.u8(), 1, 'DETAIL');
    lastSlowPollS = r.u32();

    batteryMode = r.u16();
    remCapAlarmMah = r.u16();
    remTimeAlarmMin = r.u16();
    atRateMa = r.i16();
    atRateTimeToFullMin = r.u16();
    atRateTimeToEmptyMin = r.u16();
    atRateOk = r.u16();
    maxTurboPowerCw = r.i16();
    susTurboPowerCw = r.i16();
    maxTurboCurrentMa = r.i16();
    susTurboCurrentMa = r.i16();
    turboPackRmOhm = r.u16();
    turboSysRmOhm = r.u16();
    turboEdvMv = r.u16();
    noLoadRemCapMah = r.u16();
    sohFccMah = r.u16();
    sohFccCwh = r.u16();

    qmaxMah = r.i16s(7);
    qmaxDod0 = r.i16s(7);
    rawDod0 = r.i16s(7);
    raScale = r.i16s(7);
    compRes = r.i16s(7);
    dod0 = r.i16s(7);
    dodEoc = r.i16s(7);
    cellGrid = r.i16s(7);

    packGrid = r.u8();
    lStatus = r.u8();
    stateTimeS = r.u32();
    dod0PassedQMah = r.i16();
    dod0PassedECwh = r.i16();
    dod0TimeHr16 = r.i16();
    qmaxPassedQMah = r.i16();
    qmaxTimeHr16 = r.i16();
    tempK = r.i16();
    tempA = r.i16();
    trueRemQMah = r.i16();
    trueRemECwh = r.i16();
    initialQMah = r.i16();
    initialECwh = r.i16();
    trueFccQMah = r.i16();
    trueFccECwh = r.i16();
    tSimDk = r.i16();
    tAmbientDk = r.i16();

    filtRemainingMah = r.i16();
    filtRemainingMwh = r.i16();
    filtFullChargeMah = r.i16();
    filtFullChargeMwh = r.i16();

    balanceTimeS = r.i16s(7);
    balanceDod = r.i16s(7);
    totalDodCharge = r.i16();

    ltCellMaxMv = r.i16s(7);
    ltCellMinMv = r.i16s(7);
    ltMaxDeltaCellMv = r.i16();
    ltMaxChargeMa = r.i16();
    ltMaxDischargeMa = r.i16();
    ltMaxAvgDsgMa = r.i16();
    ltMaxAvgDsgPowerCw = r.i16();
    ltMaxTempCellC = r.i8();
    ltMinTempCellC = r.i8();
    ltMaxDeltaCellTempC = r.i8();
    ltMaxTempIntC = r.i8();
    ltMinTempIntC = r.i8();
    ltMaxTempFetC = r.i8();
    ltShutdowns = r.u8();
    ltPartialResets = r.u8();
    ltFullResets = r.u8();
    ltWdtResets = r.u8();
    ltCbTimeCellH = r.u8s(7);

    ltTotalFwRuntime = r.u16();
    ltTimeInUT = r.u16();
    ltTimeInLT = r.u16();
    ltTimeInSTL = r.u16();
    ltTimeInRT = r.u16();
    ltTimeInSTH = r.u16();
    ltTimeInHT = r.u16();
    ltTimeInOT = r.u16();
  }

  factory DetailData.parse(List<int> bytes) => DetailData._(_Reader(bytes));

  static const int packetLength = 296;

  late final int lastSlowPollS;
  late final int batteryMode, remCapAlarmMah, remTimeAlarmMin, atRateMa;
  late final int atRateTimeToFullMin, atRateTimeToEmptyMin, atRateOk;
  late final int maxTurboPowerCw, susTurboPowerCw, maxTurboCurrentMa, susTurboCurrentMa;
  late final int turboPackRmOhm, turboSysRmOhm, turboEdvMv, noLoadRemCapMah;
  late final int sohFccMah, sohFccCwh;
  late final List<int> qmaxMah, qmaxDod0, rawDod0, raScale, compRes, dod0, dodEoc, cellGrid;
  late final int packGrid, lStatus, stateTimeS;
  late final int dod0PassedQMah, dod0PassedECwh, dod0TimeHr16, qmaxPassedQMah, qmaxTimeHr16;
  late final int tempK, tempA, trueRemQMah, trueRemECwh, initialQMah, initialECwh;
  late final int trueFccQMah, trueFccECwh, tSimDk, tAmbientDk;
  late final int filtRemainingMah, filtRemainingMwh, filtFullChargeMah, filtFullChargeMwh;
  late final List<int> balanceTimeS, balanceDod;
  late final int totalDodCharge;
  late final List<int> ltCellMaxMv, ltCellMinMv;
  late final int ltMaxDeltaCellMv, ltMaxChargeMa, ltMaxDischargeMa, ltMaxAvgDsgMa, ltMaxAvgDsgPowerCw;
  late final int ltMaxTempCellC, ltMinTempCellC, ltMaxDeltaCellTempC;
  late final int ltMaxTempIntC, ltMinTempIntC, ltMaxTempFetC;
  late final int ltShutdowns, ltPartialResets, ltFullResets, ltWdtResets;
  late final List<int> ltCbTimeCellH;
  late final int ltTotalFwRuntime, ltTimeInUT, ltTimeInLT, ltTimeInSTL;
  late final int ltTimeInRT, ltTimeInSTH, ltTimeInHT, ltTimeInOT;
}

// =============================================================================
// SETTINGS -- writable data flash values, read on demand (version 1)
// =============================================================================
class SettingsData {
  SettingsData._(_Reader r) {
    _checkVersion(r.u8(), 1, 'SETTINGS');
    final count = r.u8();
    for (var i = 0; i < count; i++) {
      final id = r.u8();
      final ok = r.u8() == 1;
      final value = r.i32();
      values[id] = ok ? value : null;
    }
  }

  factory SettingsData.parse(List<int> bytes) => SettingsData._(_Reader(bytes));

  /// Raw value by setting id; null when the firmware could not read it.
  final Map<int, int?> values = {};
}

// =============================================================================
// Bit names, indexed by bit number (TRM SLUUBT5C section 18). Null = reserved.
// =============================================================================
class BitRegister {
  const BitRegister(this.title, this.width, this.names);
  final String title;
  final int width;
  final List<String?> names;

  /// Names of the bits set in [value], lowest bit first.
  List<String> setBits(int value) => [
        for (var b = 0; b < width; b++)
          if ((value >> b) & 1 == 1) names[b] ?? 'bit$b',
      ];
}

const safetyBits = BitRegister('Safety', 32, [
  'CUV', 'COV', 'OCC1', 'OCC2', 'OCD1', 'OCD2', 'AOLD', 'AOLDL', //
  'ASCC', 'ASCCL', 'ASCD', 'ASCDL', 'OTC', 'OTD', 'CUVC', null,
  'OTF', 'HWDF', 'PTO', null, 'CTO', null, 'OC', 'CHGC',
  'CHGV', 'PCHGC', 'UTC', 'UTD', 'COVL', 'OCDL', null, null,
]);

const pfBits = BitRegister('Permanent Fail', 32, [
  'SUV', 'SOV', 'SOCC', 'SOCD', 'SOT', 'COVL', 'SOTF', 'QIM', //
  'CB', 'IMP', 'CD', 'VIMR', 'VIMA', 'AOLDL', 'ASCCL', 'ASCDL',
  'CFETF', 'DFETF', 'OCDL', 'FUSE', 'AFER', 'AFEC', '2LVL', null,
  'IFC', null, 'DFW', null, 'TS1', 'TS2', 'TS3', 'TS4',
]);

const operationBits = BitRegister('Operation Status', 32, [
  'PRES', 'DSG', 'CHG', 'PCHG', 'PDSG', 'FUSE', null, 'BTP_INT', //
  'SEC0', 'SEC1', 'SDV', 'SS', 'PF', 'XDSG', 'XCHG', 'SLEEP',
  'SDM', 'LED', 'AUTH', 'AUTOCALM', 'CAL', 'CAL_OFFSET', 'XL', 'SLEEPM',
  'INIT', 'SMBLCAL', 'SLPAD', 'SLPCC', 'CB', 'EMSHUT', 'PSSHUT', 'IATA_CTERM',
]);

const batteryStatusBits = BitRegister('Battery Status', 16, [
  'EC0', 'EC1', 'EC2', 'EC3', 'FD', 'FC', 'DSG', 'INIT', //
  'RTA', 'RCA', null, 'TDA', 'OTA', null, 'TCA', 'OCA',
]);

const chargingStatusBits = BitRegister('Charging Status', 24, [
  'UT', 'LT', 'STL', 'RT', 'STH', 'HT', 'OT', null, //
  'PV', 'LV', 'MV', 'HV', 'IN', 'SU', 'MCHG', 'VCT',
  'CCR', 'CVR', 'CCC', 'NCT', null, null, null, null,
]);

const gaugingStatusBits = BitRegister('Gauging / IT Status', 24, [
  'FD', 'FC', 'TD', 'TC', 'BAL_EN', 'EDV', 'DSG', 'CF', //
  'REST', null, 'RDIS', 'VOK', 'QEN', 'SLPQMAX', null, 'NSFM',
  'VDQ', 'QMAX', 'RX', 'LDMD', 'OCVFR', null, null, null,
]);

const mfgStatusBits = BitRegister('Manufacturing Status', 16, [
  'PCHG_TEST', 'CHG_TEST', 'DSG_TEST', 'GAUGE_EN', 'FET_EN', 'LF_EN', 'PF_EN', 'BBR_EN', //
  'FUSE_EN', 'LED_EN', null, null, null, 'PDSG_TEST', 'LT_TEST', 'CAL_EN',
]);

const batteryModeBits = BitRegister('Battery Mode', 16, [
  'ICC', 'PBS', null, null, null, null, null, 'CF', //
  'CC', 'PB', null, null, null, 'AM', 'CHGM', 'CAPM',
]);

const lStatusBits = BitRegister('LStatus', 8, [
  'CF0', 'CF1', 'ITEN', 'FIELD_QMAX', null, null, null, null,
]);

/// Plain-language meaning of the safety and PF flags shown as alarms.
const flagDescriptions = <String, String>{
  'CUV': 'Cell undervoltage',
  'CUVC': 'Cell undervoltage (compensated)',
  'COV': 'Cell overvoltage',
  'COVL': 'Cell overvoltage, latched',
  'OCC1': 'Overcurrent in charge 1',
  'OCC2': 'Overcurrent in charge 2',
  'OCD1': 'Overcurrent in discharge 1',
  'OCD2': 'Overcurrent in discharge 2',
  'OCDL': 'Overcurrent in discharge, latched',
  'AOLD': 'Overload in discharge',
  'AOLDL': 'Overload in discharge, latched',
  'ASCC': 'Short circuit in charge',
  'ASCCL': 'Short circuit in charge, latched',
  'ASCD': 'Short circuit in discharge',
  'ASCDL': 'Short circuit in discharge, latched',
  'OC': 'Overcharge (capacity based)',
  'CHGV': 'Overcharging voltage',
  'CHGC': 'Overcharging current',
  'PCHGC': 'Over-precharge current',
  'OTC': 'Overtemperature in charge',
  'OTD': 'Overtemperature in discharge',
  'OTF': 'FET overtemperature',
  'UTC': 'Undertemperature in charge',
  'UTD': 'Undertemperature in discharge',
  'CTO': 'Charge timeout',
  'PTO': 'Precharge timeout',
  'HWDF': 'Host watchdog fault',
};

const securityModeNames = ['Reserved', 'Full Access', 'Unsealed', 'Sealed'];

const tempSensorNames = ['Internal', 'TS1', 'TS2', 'TS3', 'TS4', 'Cell', 'FET'];
