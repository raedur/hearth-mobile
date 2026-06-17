import 'dart:convert';

/// Shared JWT helpers used by auth_service.dart and geofence_service.dart.
/// The Kotlin equivalent lives in WifiTriggerReceiver.kt (no cross-language sharing).

String? jwtClaim(String token, String claim) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    final payload = base64Url.normalize(parts[1]);
    final map = jsonDecode(utf8.decode(base64Url.decode(payload))) as Map<String, dynamic>;
    return map[claim]?.toString();
  } catch (_) {
    return null;
  }
}

bool jwtExpired(String token) {
  final exp = jwtClaim(token, 'exp');
  if (exp == null) return true;
  final expInt = int.tryParse(exp);
  if (expInt == null) return true;
  return DateTime.now().millisecondsSinceEpoch / 1000 >= expInt;
}
