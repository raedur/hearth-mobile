// Single source of truth for secure storage and shared preferences keys.
// Used by auth_service.dart, geofence_service.dart, and (by copy) WifiTriggerReceiver.kt.
const kKeyAccessToken = 'hearth_access_token';
const kKeyRefreshToken = 'hearth_refresh_token';
const kKeyBaseUrl = 'hearth_base_url';
const kKeyNonce = 'hearth_nonce';
const kKeyNonceExpiry = 'hearth_nonce_expiry';
const kPrefWifiTriggers = 'hearth_wifi_triggers';
const kPrefGeofences = 'hearth_geofences';
