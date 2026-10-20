// df_catalog.dart is generated from TI's data flash table by the firmware
// repo's tools/gen_df_catalog.py, together with the firmware's writable list.
// These pin the counts and the read-only policy so a regeneration that drifts
// shows up here.
import 'package:flutter_test/flutter_test.dart';
import 'package:hero_bms/ble/df_catalog.dart';
import 'package:hero_bms/ble/df_param.dart';

DfParam _byAddr(int addr) => dfParams.firstWhere((p) => p.addr == addr);

void main() {
  test('catalog matches the generator output', () {
    expect(dfParams.length, 999);
    expect(dfParams.where((p) => p.writable).length, 366);
    expect(dfParams.map((p) => p.addr).toSet().length, dfParams.length);
    for (final p in dfParams) {
      expect(dfClasses, contains(p.cls), reason: p.name);
    }
  });

  test('dangerous classes and parameters are read only', () {
    for (final p in dfParams) {
      if (['Calibration', 'Ra Table', 'Black Box', 'Lifetimes', 'PF Status', 'System Data']
          .contains(p.cls)) {
        expect(p.writable, isFalse, reason: '${p.cls} / ${p.name}');
      }
    }
    expect(_byAddr(0x4AE6).writable, isFalse); // SMBus Address
    expect(_byAddr(0x4800).writable, isFalse); // Mfg Status init
    expect(_byAddr(0x4D05).writable, isFalse); // Cell Configuration
    expect(_byAddr(0x4C45).writable, isFalse); // Enabled PF A
    expect(_byAddr(0x4BC0).writable, isTrue); // Enabled Protections C
    expect(_byAddr(0x4D14).writable, isTrue); // Quit Current
  });

  test('decodes and formats each kind of value', () {
    final cuv = _byAddr(0x4BC2); // I2 mV
    expect(cuv.format([0xC4, 0x09]), '2500');
    final ocd = _byAddr(0x4BED); // I2, negative
    expect(ocd.decode([0x90, 0xE8]), -6000);
    final otc = _byAddr(0x4C05); // 0.1 K shown as °C
    expect(otc.format([0xD2, 0x0C]), '55.0');
    expect(otc.displayUnit, '°C');
    expect(otc.parse('55'), 3282);
    final enC = _byAddr(0x4BC0); // H1
    expect(enC.format([0x95]), '0x95');
    expect(enC.parse('0xD5'), 0xD5);
    final name = _byAddr(0x40E3); // S21 string
    expect(name.format([7, ...'bq40z80'.codeUnits, ...List.filled(14, 0)]), 'bq40z80');
  });
}
