import 'package:encrypt/encrypt.dart';

class EncryptionService {
  // Fixed key and IV for local obfuscation. 
  // In a real production app with higher security needs, use FlutterSecureStorage 
  // or store the key securely. For this requirement, hardcoded key is sufficient.
  static final _key = Key.fromUtf8('MySecretKeyForDBPasswords123456'); // 32 chars
  static final _iv = IV.fromUtf8('MySecretIV123456'); // 16 chars
  static final _encrypter = Encrypter(AES(_key));

  static String encrypt(String text) {
    if (text.isEmpty) return text;
    try {
      return _encrypter.encrypt(text, iv: _iv).base64;
    } catch (e) {
      print('Encryption error: $e');
      return text;
    }
  }

  static String decrypt(String encryptedText) {
    if (encryptedText.isEmpty) return encryptedText;
    try {
      return _encrypter.decrypt64(encryptedText, iv: _iv);
    } catch (e) {
      // Legacy data support: If decryption fails, it means the text was saved 
      // as plain text before encryption was implemented.
      // We return it as-is so the connection still works.
      return encryptedText;
    }
  }
}
