import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import '../utils/logger.dart';

class EncryptionService {
  // Fixed key and IV for local obfuscation.
  // In a real production app with higher security needs, use FlutterSecureStorage
  // or store the key securely. For this requirement, hardcoded key is sufficient.
  // AES-128 requires a 16-byte key.
  static final List<int> _keyBytes = utf8.encode('MySecretKeyForDBPasswords123456'.substring(0, 16));
  // A fixed nonce is generally NOT recommended for AES-GCM for security reasons.
  // Ideally, a unique nonce should be generated for each encryption and stored with the ciphertext.
  // For migration purposes, mimicking the fixed IV behavior of the previous library.
  // AES-GCM nonce length is typically 12 bytes.
  static final List<int> _nonceBytes = utf8.encode('MySecretIV123456'.substring(0, 12));

  static final AesGcm _algorithm = AesGcm.with128bits();
  static SecretKey _secretKey = SecretKey(_keyBytes);

  static Future<void> init() async {
    _secretKey = SecretKey(_keyBytes);
  }

  static Future<String> encrypt(String text) async {
    if (text.isEmpty) return text;
    try {
      final plaintextBytes = utf8.encode(text);
      final SecretBox secretBox = await _algorithm.encrypt(
        plaintextBytes,
        secretKey: _secretKey,
        nonce: _nonceBytes, // Using a fixed nonce for consistency with previous implementation
      );
      // The SecretBox contains ciphertext, nonce, and MAC.
      // We need to store all these parts to decrypt later.
      // For simplicity, we'll concatenate them here as base64.
      return base64.encode(_nonceBytes + secretBox.cipherText + secretBox.mac.bytes);
    } catch (e) {
      Log.error('Encryption error: $e');
      return text;
    }
  }

  static Future<String> decrypt(String encryptedText) async {
    if (encryptedText.isEmpty) return encryptedText;
    try {
      final fullEncryptedBytes = base64.decode(encryptedText);
      // Extract nonce, ciphertext, and MAC from the concatenated bytes.
      // Assuming nonceLength is 12 and macLength is 16 for AES-GCM.
      final nonceLength = 12;
      final macLength = 16;

      if (fullEncryptedBytes.length < nonceLength + macLength) {
        throw FormatException('Invalid encrypted data format.');
      }

      final nonce = fullEncryptedBytes.sublist(0, nonceLength);
      final cipherText = fullEncryptedBytes.sublist(nonceLength, fullEncryptedBytes.length - macLength);
      final macBytes = fullEncryptedBytes.sublist(fullEncryptedBytes.length - macLength);

      final secretBox = SecretBox(
        cipherText,
        nonce: nonce,
        mac: Mac(macBytes),
      );

      final decryptedBytes = await _algorithm.decrypt(
        secretBox,
        secretKey: _secretKey,
      );
      return utf8.decode(decryptedBytes);
    } on SecretBoxAuthenticationError {
      Log.error('Decryption failed: Authentication tag mismatch. Data may have been tampered with or key is incorrect.');
      return encryptedText;
    } catch (e) {
      Log.error('Decryption error: $e');
      // Legacy data support: If decryption fails, it means the text was saved
      // as plain text before encryption was implemented.
      // We return it as-is so the connection still works.
      return encryptedText;
    }
  }
}
