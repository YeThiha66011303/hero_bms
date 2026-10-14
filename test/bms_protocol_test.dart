// Builds packets in the same order main/ble_server.cpp writes them, so a field
// added on one side but not the other shows up as a length or value mismatch.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hero_bms/ble/bms_protocol.dart';

class _W {
  final _b = BytesBuilder();
  void u8(int v) => _b.addByte(v & 0xFF);
  void u16(int v) => _b.add((ByteData(2)..setUint16(0, v & 0xFFFF, Endian.little)).buffer.asUint8List());
  void i16(int v) => u16(v);
  void u32(int v) => _b.add((ByteData(4)..setUint32(0, v & 0xFFFFFFFF, Endian.little)).buffer.asUint8List());
  void i32(int v) => u32(v);
  void arr16(List<int> v) => v.forEach(i16);
  void str(String s) {
    u8(s.length);
    _b.add(s.codeUnits);
  }

  List<int> get bytes => _b.toBytes();
}

List<int> _live() {
  final w = _W()
    ..u8(1) // version
    ..u8(0x01 | 0x04) // online, reset safe
    ..u8(6)
    ..u8(87) // rsoc
    ..u8(85)
    ..u8(1)
    ..u32(3600)
    ..u32(3600)
    ..u32(2)
    ..u16(19800) // voltage
    ..i16(-2500) // current
    ..i16(-2400)
    ..u16(2981) // 24.95 C
    ..u16(8700)
    ..u16(10000)
    ..u16(0)
    ..u16(21900)
    ..u16(0x00C0)
    ..i16(19790)
    ..i16(19780)
    ..i16(-4950)
    ..i16(-4900)
    ..arr16([3301, 3302, 3299, 3310, 3290, 3300, 0])
    ..arr16([0, 0, 0, 0, 0, 0, 0])
    ..arr16([0, 0, 0, 0, 0, 0, 0])
    ..arr16([2990, 2981, 2975, 0, 0, 2981, 3001])
    ..u32((1 << 1) | (1 << 2) | (3 << 8) | (1 << 28)) // DSG, CHG, sealed, CB
    ..u32(1 << 0) // safety: CUV
    ..u32(1 << 24) // alert: CHGV
    ..u32(0)
    ..u32(1 << 6) // gauging DSG: not charging
    ..u16((1 << 4) | (1 << 3)) // FET_EN, GAUGE_EN
    ..u32(0)
    ..u32(0)
    ..u16(42)
    ..u16(98)
    ..u16(200)
    ..u16(210)
    ..u16(65535)
    ..u32(1)
    ..u32(1200)
    ..i32(0);
  return w.bytes;
}

List<int> _detail() {
  final w = _W()
    ..u8(1)
    ..u32(3590);
  for (var i = 0; i < 17; i++) {
    w.u16(i);
  }
  for (var a = 0; a < 8; a++) {
    w.arr16(List.generate(7, (i) => a * 100 + i));
  }
  w
    ..u8(5)
    ..u8(0x04)
    ..u32(777);
  for (var i = 0; i < 15; i++) {
    w.i16(i);
  }
  for (var i = 0; i < 4; i++) {
    w.i16(1000 + i);
  }
  w
    ..arr16(List.filled(7, 1))
    ..arr16(List.filled(7, 2))
    ..i16(3)
    ..arr16(List.filled(7, 3650))
    ..arr16(List.filled(7, 2500))
    ..i16(150);
  for (var i = 0; i < 4; i++) {
    w.i16(-i);
  }
  for (final t in [45, -5, 8, 50, 0, 60]) {
    w.u8(t);
  }
  for (var i = 0; i < 4; i++) {
    w.u8(i);
  }
  for (var i = 0; i < 7; i++) {
    w.u8(i * 2);
  }
  for (var i = 0; i < 8; i++) {
    w.u16(500 + i);
  }
  return w.bytes;
}

void main() {
  test('LIVE layout is 152 bytes and decodes', () {
    final bytes = _live();
    expect(bytes.length, LiveData.packetLength);

    final d = LiveData.parse(bytes);
    expect(d.online, isTrue);
    expect(d.resetSafe, isTrue);
    expect(d.staticValid, isFalse);
    expect(d.cells, [3301, 3302, 3299, 3310, 3290, 3300]);
    expect(d.cellMax, 3310);
    expect(d.cellMinIndex, 4);
    expect(d.cellSpread, 20);
    expect(d.current, closeTo(-2.5, 1e-9));
    expect(d.temperatureC, closeTo(24.95, 1e-9));
    expect(dKToC(d.tempsDk[3]), isNull);
    expect(d.dsgFet && d.chgFet && d.balancing, isTrue);
    expect(securityModeNames[d.securityMode], 'Sealed');
    expect(d.gaugingState, 'Discharging');
    expect(safetyBits.setBits(d.safetyStatus), ['CUV']);
    expect(safetyBits.setBits(d.safetyAlert), ['CHGV']);
    expect(d.fetEnabled, isTrue);
    // Last fields catch any drift in the middle of the packet.
    expect(d.avgTimeToFullMin, 65535);
    expect(d.resetCount, 1);
    expect(d.resetLastAtS, 1200);
  });

  test('LIVE rejects truncated packets and unknown versions', () {
    final bytes = _live();
    expect(() => LiveData.parse(bytes.sublist(0, 100)), throwsA(isA<ProtocolException>()));
    expect(() => LiveData.parse([2, ...bytes.skip(1)]), throwsA(isA<ProtocolException>()));
  });

  test('DETAIL layout is 296 bytes and decodes', () {
    final bytes = _detail();
    expect(bytes.length, DetailData.packetLength);

    final x = DetailData.parse(bytes);
    expect(x.lastSlowPollS, 3590);
    expect(x.sohFccCwh, 16);
    expect(x.qmaxMah[2], 2);
    expect(x.cellGrid[6], 706);
    expect(x.stateTimeS, 777);
    expect(x.tAmbientDk, 14);
    expect(x.filtFullChargeMwh, 1003);
    expect(x.ltCellMinMv.first, 2500);
    expect(x.ltMinTempCellC, -5);
    expect(x.ltCbTimeCellH.last, 12);
    expect(x.ltTimeInOT, 507);
  });

  test('INFO decodes strings and date', () {
    final w = _W()
      ..u8(1)
      ..u8(0x07)
      ..u8(6)
      ..u8(0x40)
      ..u16(0x0436)
      ..u16(0x4800)
      ..u16(1234)
      ..u16(10000)
      ..u16(19200)
      ..u16(((2025 - 1980) << 9) | (3 << 5) | 14)
      ..u16(0x0018)
      ..str('Texas Inst.')
      ..str('bq40z80')
      ..str('LFP');
    final i = InfoData.parse(w.bytes);
    expect(i.valid && i.protCValid && i.mfgStatusInitValid, isTrue);
    expect(i.deviceName, 'bq40z80');
    expect(i.chemistry, 'LFP');
    expect(i.manufactureDateText, '2025-03-14');
    expect(i.isLfpChemId, isTrue);
  });
}
