package com.umma.translation.translation

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telephony.SmsManager
import androidx.annotation.NonNull
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/** Handles the "translation/emergency_sms" channel: sends the emergency
 * alert (message + GPS link, built on the Dart side) via SmsManager.
 * iOS has no equivalent — this feature is Android-only by design.
 *
 * Sends are confirmed via PendingIntent broadcast, not fire-and-forget:
 * `SmsManager.sendMultipartTextMessage` returns immediately once the
 * message is handed to the radio, before the radio has actually reported
 * whether it went out. Passing null sentIntents (the previous behavior)
 * meant a genuine failure — no SIM, no signal, radio rejected it — was
 * silently swallowed and the app told the user "alert sent" regardless.
 */
class MainActivity : FlutterActivity() {
    private val emergencySmsChannel = "translation/emergency_sms"
    private val requestCodeCounter = AtomicInteger(0)

    // Generous but bounded: if the OS never delivers a sent-result broadcast
    // (has happened on some OEM SMS stacks), don't hang the UI forever.
    private val sendTimeoutMs = 15_000L

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
                    sendWithConfirmation(phoneNumber, message, result)
                } catch (e: Exception) {
                    result.error("SMS_SEND_FAILED", e.message, null)
                }
            }
    }

    private fun sendWithConfirmation(phoneNumber: String, message: String, result: MethodChannel.Result) {
        val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(SmsManager::class.java)
        } else {
            @Suppress("DEPRECATION")
            SmsManager.getDefault()
        }
        val parts = smsManager.divideMessage(message)
        val requestCode = requestCodeCounter.incrementAndGet()
        val action = "$packageName.EMERGENCY_SMS_SENT_$requestCode"

        val remaining = AtomicInteger(parts.size)
        val resultDelivered = AtomicBoolean(false)
        val mainHandler = Handler(Looper.getMainLooper())
        var receiverRef: BroadcastReceiver? = null
        var timeoutRunnable: Runnable? = null

        fun finish(block: () -> Unit) {
            if (!resultDelivered.compareAndSet(false, true)) return
            timeoutRunnable?.let { mainHandler.removeCallbacks(it) }
            receiverRef?.let {
                try {
                    unregisterReceiver(it)
                } catch (_: IllegalArgumentException) {
                    // Already unregistered (e.g. by the timeout path) — fine.
                }
            }
            block()
        }

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (resultCode) {
                    android.app.Activity.RESULT_OK -> {
                        if (remaining.decrementAndGet() <= 0) {
                            finish { result.success(null) }
                        }
                    }
                    else -> {
                        val reason = describeSmsError(resultCode)
                        finish { result.error("SMS_SEND_FAILED", reason, null) }
                    }
                }
            }
        }
        receiverRef = receiver

        ContextCompat.registerReceiver(
            this,
            receiver,
            IntentFilter(action),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )

        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_IMMUTABLE else 0)
        val sentIntent = PendingIntent.getBroadcast(
            this,
            requestCode,
            Intent(action).setPackage(packageName),
            piFlags,
        )
        val sentIntents = ArrayList<PendingIntent>(parts.size).apply {
            repeat(parts.size) { add(sentIntent) }
        }

        timeoutRunnable = Runnable {
            finish {
                result.error(
                    "SMS_SEND_TIMEOUT",
                    "No confirmation from the phone's SMS radio within ${sendTimeoutMs / 1000}s.",
                    null,
                )
            }
        }
        mainHandler.postDelayed(timeoutRunnable, sendTimeoutMs)

        smsManager.sendMultipartTextMessage(phoneNumber, null, parts, sentIntents, null)
    }

    private fun describeSmsError(resultCode: Int): String = when (resultCode) {
        SmsManager.RESULT_ERROR_NO_SERVICE -> "No cellular service — the phone has no signal or no active SIM."
        SmsManager.RESULT_ERROR_RADIO_OFF -> "Airplane mode is on, or the radio is off."
        SmsManager.RESULT_ERROR_NULL_PDU -> "The message could not be encoded for sending."
        SmsManager.RESULT_ERROR_GENERIC_FAILURE -> "The SMS failed to send (generic radio failure)."
        SmsManager.RESULT_ERROR_LIMIT_EXCEEDED -> "Too many messages sent recently — the radio is rate-limiting SMS."
        else -> "SMS send failed with radio result code $resultCode."
    }
}
