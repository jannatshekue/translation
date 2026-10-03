package com.umma.translation.translation

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.ActivityNotFoundException
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.ContactsContract
import android.telephony.SmsManager
import android.window.SplashScreenView
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
    private val contactsChannel = "translation/contacts"
    private val pickContactRequestCode = 7301
    private var pendingContactResult: MethodChannel.Result? = null
    private val requestCodeCounter = AtomicInteger(0)

    // Android 12+ fades its own launch screen out the moment the activity
    // draws, which can be a few frames before Flutter has painted anything —
    // the icon tile visibly dips. The launch screen shows exactly Flutter's
    // first frame, so instead it is held until Flutter reports that frame is
    // on screen and then removed instantly: the hand-over is invisible.
    private val uiHandler = Handler(Looper.getMainLooper())
    private var heldSplash: SplashScreenView? = null
    private var flutterUiDisplayed = false

    // Generous but bounded: if the OS never delivers a sent-result broadcast
    // (has happened on some OEM SMS stacks), don't hang the UI forever.
    private val sendTimeoutMs = 15_000L

    override fun onCreate(savedInstanceState: Bundle?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            splashScreen.setOnExitAnimationListener { splashView ->
                if (flutterUiDisplayed) {
                    splashView.remove()
                } else {
                    heldSplash = splashView
                    // Safety net: never leave the launch screen up if Flutter
                    // somehow never reports its first frame.
                    uiHandler.postDelayed({ releaseSplash() }, 2500)
                }
            }
        }
        super.onCreate(savedInstanceState)
    }

    override fun onFlutterUiDisplayed() {
        super.onFlutterUiDisplayed()
        flutterUiDisplayed = true
        releaseSplash()
    }

    private fun releaseSplash() {
        heldSplash?.remove()
        heldSplash = null
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Contact picker: launches the system phonebook and returns the one
        // contact the person taps. The picker grants this app temporary read
        // access to just that row, so no READ_CONTACTS permission is needed.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, contactsChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "pickContact") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingContactResult != null) {
                    result.error("ALREADY_ACTIVE", "The phonebook is already open.", null)
                    return@setMethodCallHandler
                }
                val intent = Intent(Intent.ACTION_PICK, ContactsContract.CommonDataKinds.Phone.CONTENT_URI)
                try {
                    pendingContactResult = result
                    startActivityForResult(intent, pickContactRequestCode)
                } catch (e: ActivityNotFoundException) {
                    pendingContactResult = null
                    result.error("NO_CONTACTS_APP", "No contacts app was found on this phone.", null)
                }
            }

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

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != pickContactRequestCode) {
            @Suppress("DEPRECATION")
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val pending = pendingContactResult ?: return
        pendingContactResult = null
        val uri = data?.data
        if (resultCode != android.app.Activity.RESULT_OK || uri == null) {
            pending.success(null)
            return
        }
        try {
            val projection = arrayOf(
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ContactsContract.CommonDataKinds.Phone.NUMBER,
            )
            contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    pending.success(mapOf("name" to cursor.getString(0), "number" to cursor.getString(1)))
                    return
                }
            }
            pending.success(null)
        } catch (e: Exception) {
            pending.error("CONTACT_READ_FAILED", "Could not read that contact.", null)
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
                    "The phone did not confirm the message was sent within ${sendTimeoutMs / 1000} seconds. Check your signal.",
                    null,
                )
            }
        }
        mainHandler.postDelayed(timeoutRunnable, sendTimeoutMs)

        smsManager.sendMultipartTextMessage(phoneNumber, null, parts, sentIntents, null)
    }

    private fun describeSmsError(resultCode: Int): String = when (resultCode) {
        SmsManager.RESULT_ERROR_NO_SERVICE -> "No mobile signal, or no active SIM card."
        SmsManager.RESULT_ERROR_RADIO_OFF -> "Airplane mode is on or the mobile network is switched off."
        SmsManager.RESULT_ERROR_NULL_PDU -> "The message could not be prepared for sending."
        SmsManager.RESULT_ERROR_GENERIC_FAILURE -> "The phone could not send the message. Check your SIM, signal and airtime."
        SmsManager.RESULT_ERROR_LIMIT_EXCEEDED -> "Too many messages were sent recently. Wait a moment and try again."
        else -> "The message could not be sent (code $resultCode)."
    }
}
