import 'package:flutter_test/flutter_test.dart';
import 'package:translation/models/emergency_contact.dart';

void main() {
  group('normalizePhoneNumber', () {
    test('strips spaces, dashes and brackets', () {
      expect(normalizePhoneNumber('0712 345-678'), '0712345678');
      expect(normalizePhoneNumber('(020) 555 1234'), '0205551234');
    });

    test('keeps a leading plus', () {
      expect(normalizePhoneNumber('+254 712 345 678'), '+254712345678');
    });

    test('accepts short emergency numbers', () {
      expect(normalizePhoneNumber('112'), '112');
    });

    test('rejects junk and too-short input', () {
      expect(normalizePhoneNumber(''), isNull);
      expect(normalizePhoneNumber('ab'), isNull);
      expect(normalizePhoneNumber('12'), isNull);
    });
  });

  group('EmergencyContact JSON', () {
    test('contacts saved before selection existed load as selected', () {
      final c = EmergencyContact.fromJson({'label': 'Mom', 'number': '0712345678'});
      expect(c.selected, isTrue);
    });

    test('selection round-trips', () {
      const c = EmergencyContact(label: 'Mom', number: '0712345678', selected: false);
      expect(EmergencyContact.fromJson(c.toJson()).selected, isFalse);
    });
  });
}
