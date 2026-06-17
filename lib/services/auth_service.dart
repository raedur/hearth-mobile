import 'dart:async';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_service.dart';
import 'jwt_utils.dart';
import 'storage_keys.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final _rng = Random.secure();

  // Mutex: if a refresh is already in flight, subsequent callers wait for it
  // rather than firing a second concurrent request with the same refresh token.
  Completer<bool>? _activeRefresh;

  // ---------- token storage ----------

  Future<String?> getAccessToken() => _storage.read(key: kKeyAccessToken);
  Future<String?> getRefreshToken() => _storage.read(key: kKeyRefreshToken);

  Future<void> storeTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    final baseUrl = jwtClaim(accessToken, 'baseUrl');
    if (baseUrl != null) {
      await _storage.write(key: kKeyBaseUrl, value: baseUrl);
      ApiService.baseUrl = baseUrl;
    }
    await Future.wait([
      _storage.write(key: kKeyAccessToken, value: accessToken),
      _storage.write(key: kKeyRefreshToken, value: refreshToken),
    ]);
  }

  Future<void> clearTokens() async {
    await Future.wait([
      _storage.delete(key: kKeyAccessToken),
      _storage.delete(key: kKeyRefreshToken),
      _storage.delete(key: kKeyBaseUrl),
      _storage.delete(key: kKeyNonce),
      _storage.delete(key: kKeyNonceExpiry),
    ]);
    ApiService.baseUrl = null;
  }

  Future<bool> hasValidToken() async {
    await _restoreBaseUrl();
    final token = await getAccessToken();
    if (token == null) return false;
    if (!jwtExpired(token)) return true;
    return silentRefresh();
  }

  Future<void> _restoreBaseUrl() async {
    final url = await _storage.read(key: kKeyBaseUrl);
    if (url != null) ApiService.baseUrl = url;
  }

  // ---------- silent refresh (public — used by ApiService on 401) ----------

  Future<bool> silentRefresh() async {
    // If a refresh is already in flight, join it instead of firing a second one.
    // This prevents two concurrent 401s from both sending the same refresh token,
    // which would cause the second call to fail with an already-rotated token.
    if (_activeRefresh != null) return _activeRefresh!.future;

    _activeRefresh = Completer<bool>();
    try {
      final result = await _doRefresh();
      _activeRefresh!.complete(result);
      return result;
    } catch (e) {
      _activeRefresh!.completeError(e);
      rethrow;
    } finally {
      _activeRefresh = null;
    }
  }

  Future<bool> _doRefresh() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken == null || ApiService.baseUrl == null) return false;
    try {
      final result = await ApiService().refresh(refreshToken);
      if (result == null) return false;
      await storeTokens(
        accessToken: result['token'] as String,
        refreshToken: result['refreshToken'] as String,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------- nonce / login initiation ----------

  Future<String> generateNonce() async {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final nonce = List.generate(6, (_) => chars[_rng.nextInt(chars.length)]).join();
    final expiry = DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch;
    await Future.wait([
      _storage.write(key: kKeyNonce, value: nonce),
      _storage.write(key: kKeyNonceExpiry, value: expiry.toString()),
    ]);
    return nonce;
  }

  // ---------- deep link handling ----------

  void listenForAuthDeepLink({
    required void Function(String accessToken, String refreshToken) onSuccess,
    required void Function(String error) onError,
  }) {
    AppLinks().uriLinkStream.listen((uri) async {
      if (uri.scheme != 'hearth' || uri.host != 'auth') return;

      final token = uri.queryParameters['token'];
      final refresh = uri.queryParameters['refresh'];
      if (token == null || refresh == null) {
        onError('Invalid deep link — missing token or refresh');
        return;
      }

      final nonceOk = await _validateNonce(token);
      if (!nonceOk) {
        onError('Nonce mismatch or expired — auth rejected');
        return;
      }

      await storeTokens(accessToken: token, refreshToken: refresh);
      onSuccess(token, refresh);
    });
  }

  Future<bool> _validateNonce(String token) async {
    final stored = await _storage.read(key: kKeyNonce);
    final expiryStr = await _storage.read(key: kKeyNonceExpiry);
    if (stored == null || expiryStr == null) return false;

    final expiry = int.tryParse(expiryStr);
    if (expiry == null || DateTime.now().millisecondsSinceEpoch > expiry) return false;

    final nonce = jwtClaim(token, 'nonce');
    if (nonce == null || nonce != stored) return false;

    // Consume nonce atomically before returning success
    await Future.wait([
      _storage.delete(key: kKeyNonce),
      _storage.delete(key: kKeyNonceExpiry),
    ]);
    return true;
  }

  String? getMemberName(String token) => jwtClaim(token, 'name');
}
