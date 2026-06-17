package au.id.craig.hearth_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.NetworkInfo
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.util.Base64
import androidx.core.app.NotificationCompat
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

// Key names must stay in sync with lib/services/storage_keys.dart
private const val KEY_ACCESS_TOKEN = "hearth_access_token"
private const val KEY_REFRESH_TOKEN = "hearth_refresh_token"
private const val KEY_BASE_URL = "hearth_base_url"
private const val PREF_WIFI_TRIGGERS = "hearth_wifi_triggers"

class WifiTriggerReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != WifiManager.NETWORK_STATE_CHANGED_ACTION) return

        @Suppress("DEPRECATION")
        val networkInfo: NetworkInfo? = if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(WifiManager.EXTRA_NETWORK_INFO, NetworkInfo::class.java)
        } else {
            intent.getParcelableExtra(WifiManager.EXTRA_NETWORK_INFO)
        }
        if (networkInfo?.isConnected != true) return

        val ssid = resolveSsid(context, intent) ?: return
        if (ssid.isEmpty() || ssid == "<unknown ssid>") return

        val message = matchedTrigger(context, ssid) ?: return

        val pendingResult = goAsync()
        Thread {
            try {
                val creds = validCredentials(context)
                if (creds == null) {
                    showAuthFailedNotification(context)
                    return@Thread
                }
                val (baseUrl, token) = creds
                post("$baseUrl/api/capture", token, """{"text":${jsonString(message)}}""")
            } finally {
                pendingResult.finish()
            }
        }.start()
    }

    private fun resolveSsid(context: Context, intent: Intent): String? {
        @Suppress("DEPRECATION")
        val info: WifiInfo? = if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(WifiManager.EXTRA_WIFI_INFO, WifiInfo::class.java)
        } else {
            intent.getParcelableExtra(WifiManager.EXTRA_WIFI_INFO)
        }
        val fromIntent = info?.ssid?.trim('"')
        if (!fromIntent.isNullOrEmpty()) return fromIntent

        @Suppress("DEPRECATION")
        val wm = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        @Suppress("DEPRECATION")
        return wm.connectionInfo?.ssid?.trim('"')
    }

    private fun matchedTrigger(context: Context, ssid: String): String? {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val triggers = prefs.getStringSet("flutter.$PREF_WIFI_TRIGGERS", null) ?: return null
        return triggers.firstNotNullOfOrNull { entry ->
            val i = entry.indexOf('|')
            if (i != -1 && entry.substring(0, i) == ssid) entry.substring(i + 1) else null
        }
    }

    // Returns a valid (non-expired) token, refreshing silently if needed.
    private fun validCredentials(context: Context): Pair<String, String>? {
        return try {
            val masterKey = MasterKey.Builder(context)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()
            val prefs = EncryptedSharedPreferences.create(
                context,
                "FlutterSecureStorage",
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
            val baseUrl = prefs.getString(KEY_BASE_URL, null) ?: return null
            var token = prefs.getString(KEY_ACCESS_TOKEN, null) ?: return null

            if (jwtExpired(token)) {
                val refreshToken = prefs.getString(KEY_REFRESH_TOKEN, null) ?: return null
                token = refreshToken(baseUrl, refreshToken, prefs) ?: return null
            }

            Pair(baseUrl, token)
        } catch (_: Exception) {
            null
        }
    }

    private fun refreshToken(
        baseUrl: String,
        refreshToken: String,
        prefs: android.content.SharedPreferences,
    ): String? {
        return try {
            val conn = URL("$baseUrl/api/refresh").openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/json")
            conn.connectTimeout = 10_000
            conn.readTimeout = 10_000
            conn.doOutput = true
            conn.outputStream.use { it.write("""{"refreshToken":${jsonString(refreshToken)}}""".toByteArray()) }
            if (conn.responseCode != 200) return null
            val body = conn.inputStream.bufferedReader().readText()
            conn.disconnect()
            val json = JSONObject(body)
            val newToken = json.getString("token")
            val newRefresh = json.getString("refreshToken")
            prefs.edit()
                .putString(KEY_ACCESS_TOKEN, newToken)
                .putString(KEY_REFRESH_TOKEN, newRefresh)
                .apply()
            newToken
        } catch (_: Exception) {
            null
        }
    }

    private fun post(url: String, token: String, body: String) {
        try {
            val conn = URL(url).openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Authorization", "Bearer $token")
            conn.setRequestProperty("Content-Type", "application/json")
            conn.connectTimeout = 10_000
            conn.readTimeout = 10_000
            conn.doOutput = true
            conn.outputStream.use { it.write(body.toByteArray()) }
            conn.responseCode
            conn.disconnect()
        } catch (_: Exception) {}
    }

    // JWT helpers — mirrors jwt_utils.dart (no cross-language sharing possible)
    private fun jwtExpired(token: String): Boolean {
        return try {
            val payload = token.split(".").getOrNull(1) ?: return true
            val decoded = String(Base64.decode(payload, Base64.URL_SAFE or Base64.NO_PADDING))
            val exp = JSONObject(decoded).optLong("exp", 0L)
            exp == 0L || System.currentTimeMillis() / 1000 >= exp
        } catch (_: Exception) {
            true
        }
    }

    private fun showAuthFailedNotification(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel("hearth_alerts", "Hearth Alerts", NotificationManager.IMPORTANCE_HIGH)
            )
        }
        val notification = NotificationCompat.Builder(context, "hearth_alerts")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("Hearth")
            .setContentText("A WiFi trigger failed — open Hearth to reconnect.")
            .setAutoCancel(true)
            .build()
        nm.notify(998, notification)
    }

    private fun jsonString(s: String) = "\"${s.replace("\\", "\\\\").replace("\"", "\\\"")}\""
}
