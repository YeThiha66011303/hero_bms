// The settings list must match kItems in the firmware's main/df_settings.cpp.
// These tests catch the mistakes that are easy to make when editing it by hand:
// duplicate ids, a partner that does not exist, or a pair whose order rules
// contradict each other.
import 'package:flutter_test/flutter_test.dart';
import 'package:hero_bms/ble/bms_protocol.dart';
import 'package:hero_bms/ble/bms_settings.dart';

void main() {
  test('parses a SETTINGS packet, including an unreadable entry', () {
    final bytes = [
      1, 2, // version, count
      10, 1, 0xC4, 0x09, 0x00, 0x00, // id 10 = 2500 mV, read OK
      40, 0, 0x00, 0x00, 0x00, 0x00, // id 40, read failed
    ];
    final s = SettingsData.parse(bytes);
    expect(s.values[10], 2500);
    expect(s.values.containsKey(40), isTrue);
    expect(s.values[40], isNull);
  });

  test('rejects an unknown SETTINGS version', () {
    expect(() => SettingsData.parse([2, 0]), throwsA(isA<ProtocolException>()));
  });

  test('ids are unique and match the firmware list', () {
    final ids = settingDefs.map((d) => d.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids, [
      1, 2, 3, 4, 5, 6, 7, 8, 9, 60, //
      10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, //
      30, 31, 32, 33, 34, 35, 40, 41, 42, 43, 44, 45, 46, 47, 50, 51, 52, 53,
    ]);
  });

  test('every partner exists and threshold/recovery pairs agree', () {
    for (final d in settingDefs.where((d) => d.partner != 0)) {
      final p = settingById(d.partner);
      expect(p, isNotNull, reason: '${d.name} partner ${d.partner}');
      expect(d.order, isNot(0), reason: d.name);
      // Charging voltages point at COV without COV pointing back.
      if (p!.partner == d.id) expect(p.order, -d.order, reason: '${d.name} / ${p.name}');
    }
  });

  test('every setting belongs to a listed group', () {
    for (final d in settingDefs) {
      expect(settingGroups, contains(d.group), reason: d.name);
    }
  });

  test('temperatures convert to and from 0.1 K', () {
    final otc = settingById(40)!;
    expect(otc.format(3282), '55.0');
    expect(otc.parse('55'), 3282);
    expect(settingById(44)!.parse('-10'), 2632);
  });

  test('validation enforces limits and partner order', () {
    final cuv = settingById(10)!;
    final current = {10: 2500, 11: 3000};
    expect(validateSetting(cuv, 2600, current), isNull);
    expect(validateSetting(cuv, 3000, current), isNotNull); // not below recovery
    expect(validateSetting(cuv, 1900, current), isNotNull); // below limit
  });
}
