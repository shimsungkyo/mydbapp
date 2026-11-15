import 'package:flutter_test/flutter_test.dart';
import 'package:mydbapp/services/encryption_service.dart';

void main() {
  setUpAll(() async {
    await EncryptionService.init();
  });

  group('EncryptionService Tests', () {
    test('Encrypt and Decrypt normal string', () async {
      const originalText = 'my_secret_db_password_123!@#';
      final encrypted = await EncryptionService.encrypt(originalText);
      expect(encrypted, isNot(equals(originalText)));

      final decrypted = await EncryptionService.decrypt(encrypted);
      expect(decrypted, equals(originalText));
    });

    test('Empty string handling', () async {
      expect(await EncryptionService.encrypt(''), equals(''));
      expect(await EncryptionService.decrypt(''), equals(''));
    });

    test('Fallback to original text on invalid encrypted data (legacy plain text)', () async {
      const plainText = 'unencrypted_legacy_password';
      final decrypted = await EncryptionService.decrypt(plainText);
      expect(decrypted, equals(plainText));
    });
  });
}
