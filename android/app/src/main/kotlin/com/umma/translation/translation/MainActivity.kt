package com.umma.translation.translation

import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Handles the "translation/emergency_sms" channel: sends the emergency
 * alert (message + GPS link, built on the Dart side) via SmsManager.
 * iOS has no equivalent — this feature is Android-only by design. */
class MainActivity : FlutterActivity() {
    private val emergencySmsChannel = "translation/emergency_sms"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, emergencySmsChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "sendSms") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val phoneNumber = call.argument<String>("phoneNumber")
                val message = call.argument<String>("message")
                if (phoneNumber.isNullOrBlank() || message.isNullOrBlank()) {
                    result.error("INVALID_ARGUMENT", "phoneNumber and message are required", null)
                    return@setMethodCallHandler
                }

                if (checkSelfPermission(android.Manifest.permission.SEND_SMS)
                    != PackageManager.PERMISSION_GRANTED
                ) {
                    result.error("PERMISSION_DENIED", "SEND_SMS permission not granted", null)
                    return@setMethodCallHandler
                }

                try {
                    val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        getSystemService(SmsManager::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        SmsManager.getDefault()
                    }
                    val parts = smsManager.divideMessage(message)
                    smsManager.sendMultipartTextMessage(phoneNumber, null, parts, null, null)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("SMS_SEND_FAILED", e.message, null)
                }
            }
    }
}
