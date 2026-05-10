import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// End-to-end encryption service using AES-256-GCM.
///
/// The encryption key is derived from a user-chosen passphrase via PBKDF2.
/// The salt is derived deterministically from the passphrase (via SHA-256)
/// so that both devices with the same passphrase produce the same key.
/// Each message gets a unique random nonce (IV). The server only ever sees
/// encrypted ciphertext — even if compromised, data is unreadable.
class CryptoService {
  static const _passphraseKey = 'e2e_passphrase';
  static const _pbkdf2Iterations = 100000;
  static const _keyBits = 256;

  final _algorithm = AesGcm.with256bits();
  SecretKey? _secretKey;
  String? _passphrase;

  bool get isConfigured => _secretKey != null;
  String? get passphrase => _passphrase;

  /// Derive a key from a passphrase and store it.
  Future<void> configure(String passphrase) async {
    _passphrase = passphrase;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_passphraseKey, passphrase);

    // Derive salt deterministically from the passphrase so both devices
    // with the same passphrase produce the same encryption key.
    // (Previously each device generated a random salt, meaning the keys
    //  never matched and all encrypted messages were silently dropped.)
    final saltInput = utf8.encode('NM_E2E_SALT_$passphrase');
    final saltHash = await Sha256().hash(saltInput);
    final salt = saltHash.bytes.sublist(0, 16);

    _secretKey = await _deriveKey(passphrase, salt);
  }

  /// Try to load a previously stored passphrase.
  Future<bool> loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_passphraseKey);
    if (saved != null && saved.isNotEmpty) {
      await configure(saved);
      return true;
    }
    return false;
  }

  /// Clear stored passphrase (on unpair).
  Future<void> clear() async {
    _secretKey = null;
    _passphrase = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_passphraseKey);
  }

  /// Encrypt a JSON message map → base64 ciphertext string.
  Future<String> encrypt(Map<String, dynamic> message) async {
    if (_secretKey == null) {
      throw StateError('CryptoService not configured — call configure() first');
    }

    final plaintext = utf8.encode(jsonEncode(message));
    final nonce = _algorithm.newNonce();

    final secretBox = await _algorithm.encrypt(
      plaintext,
      secretKey: _secretKey!,
      nonce: nonce,
    );

    // Wire format: nonce + ciphertext + mac (all concatenated, then base64)
    final combined = Uint8List.fromList([
      ...secretBox.nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);

    return base64Encode(combined);
  }

  /// Decrypt a base64 ciphertext string → JSON message map.
  Future<Map<String, dynamic>?> decrypt(String ciphertext) async {
    if (_secretKey == null) return null;

    try {
      final combined = base64Decode(ciphertext);

      // AES-GCM nonce is 12 bytes, MAC is 16 bytes
      const nonceLen = 12;
      const macLen = 16;

      if (combined.length < nonceLen + macLen + 1) return null;

      final nonce = combined.sublist(0, nonceLen);
      final ct = combined.sublist(nonceLen, combined.length - macLen);
      final mac = combined.sublist(combined.length - macLen);

      final secretBox = SecretBox(
        ct,
        nonce: nonce,
        mac: Mac(mac),
      );

      final plaintext = await _algorithm.decrypt(
        secretBox,
        secretKey: _secretKey!,
      );

      return jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
    } catch (_) {
      // Decryption failed — wrong key, corrupted data, or tampered message
      return null;
    }
  }

  Future<SecretKey> _deriveKey(String passphrase, List<int> salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _pbkdf2Iterations,
      bits: _keyBits,
    );

    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
  }

  static final _rng = Random.secure();
  static int _secureRandom() => _rng.nextInt(256);
}
