package com.example.suraksha_sos

import android.Manifest
import android.app.Activity
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
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Sends the SOS text straight from the phone, with no SMS app and no tap on
 * Send. Needs the SEND_SMS permission, which Google Play restricts, so this is
 * meant for APKs installed directly.
 */
class MainActivity : FlutterActivity() {
    private var pendingPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasPermission" -> result.success(hasSmsPermission())
                    "requestPermission" -> requestSmsPermission(result)
                    "send" -> sendSms(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasSmsPermission() =
        checkSelfPermission(Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED

    private fun requestSmsPermission(result: MethodChannel.Result) {
        if (hasSmsPermission()) {
            result.success(true)
            return
        }
        if (pendingPermission != null) {
            result.success(false)
            return
        }
        pendingPermission = result
        requestPermissions(arrayOf(Manifest.permission.SEND_SMS), REQUEST_SMS)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_SMS) {
            pendingPermission?.success(
                grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            )
            pendingPermission = null
        }
    }

    /**
     * Replies with a map of number -> true when every part of the message to
     * that number was accepted by the phone's radio, false otherwise.
     */
    private fun sendSms(call: MethodCall, result: MethodChannel.Result) {
        val numbers = call.argument<List<String>>("numbers").orEmpty()
        val body = call.argument<String>("body").orEmpty()
        if (!hasSmsPermission()) {
            result.error("no_permission", "SEND_SMS is not granted", null)
            return
        }
        if (numbers.isEmpty() || body.isEmpty()) {
            result.error("bad_args", "numbers and body are required", null)
            return
        }

        val sms: SmsManager? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(SmsManager::class.java)
        } else {
            @Suppress("DEPRECATION")
            SmsManager.getDefault()
        }
        if (sms == null) {
            result.error("no_sms", "This device cannot send SMS", null)
            return
        }

        val parts = sms.divideMessage(body)
        val action = "$packageName.SMS_SENT.${System.nanoTime()}"
        val accepted = HashMap<String, Boolean>()
        val reported = HashMap<String, Int>()
        numbers.forEach { accepted[it] = true }
        var remaining = numbers.size * parts.size
        var finished = false
        val handler = Handler(Looper.getMainLooper())
        lateinit var receiver: BroadcastReceiver

        fun complete() {
            if (finished) return
            finished = true
            handler.removeCallbacksAndMessages(null)
            try {
                unregisterReceiver(receiver)
            } catch (_: IllegalArgumentException) {
            }
            result.success(accepted)
        }

        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val number = intent.getStringExtra(EXTRA_NUMBER) ?: return
                if (resultCode != Activity.RESULT_OK) accepted[number] = false
                reported[number] = (reported[number] ?: 0) + 1
                if (--remaining <= 0) complete()
            }
        }

        val filter = IntentFilter(action)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }

        // The radio always reports back, but never wait on it forever.
        handler.postDelayed({
            for (n in numbers) if ((reported[n] ?: 0) < parts.size) accepted[n] = false
            complete()
        }, SEND_TIMEOUT_MS)

        var requestCode = 0
        for (number in numbers) {
            val sentIntents = ArrayList<PendingIntent>()
            for (i in parts.indices) {
                val intent = Intent(action).setPackage(packageName).putExtra(EXTRA_NUMBER, number)
                sentIntents.add(
                    PendingIntent.getBroadcast(
                        this,
                        requestCode++,
                        intent,
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                    )
                )
            }
            try {
                sms.sendMultipartTextMessage(number, null, parts, sentIntents, null)
            } catch (e: Exception) {
                accepted[number] = false
                reported[number] = parts.size
                remaining -= parts.size
            }
        }
        if (remaining <= 0) complete()
    }

    private companion object {
        const val CHANNEL = "com.example.suraksha_sos/sms"
        const val EXTRA_NUMBER = "number"
        const val REQUEST_SMS = 7311
        const val SEND_TIMEOUT_MS = 30_000L
    }
}
