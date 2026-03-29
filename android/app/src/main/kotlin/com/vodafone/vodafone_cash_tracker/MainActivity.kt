package com.vodafone.vodafone_cash_tracker

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val METHOD_CHANNEL = "com.vodafone.vodafone_cash_tracker/ussd_method"
    private val EVENT_CHANNEL = "com.vodafone.vodafone_cash_tracker/ussd_event"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "runUssd" -> {
                    val code = call.argument<String>("code")
                    val pin = call.argument<String>("pin")
                    val sessionId = call.argument<String>("sessionId")
                    UssdAccessibilityService.prepareNewUssdSession(pin, sessionId)
                    dialUssdCode(code)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    UssdAccessibilityService.eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    UssdAccessibilityService.eventSink = null
                }
            }
        )
    }

    private fun dialUssdCode(code: String?) {
        if (code == null) return
        val encodedHash = Uri.encode("#")
        val ussdParam = code.replace("#", encodedHash)
        val intent = Intent(Intent.ACTION_CALL, Uri.parse("tel:$ussdParam"))
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }
}
