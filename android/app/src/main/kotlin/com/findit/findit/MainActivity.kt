package com.findit.findit

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.findit.findit/volume_keys"
    private val LOST_PHONE_CHANNEL = "com.findit.findit/lost_phone"
    private var methodChannel: MethodChannel? = null
    private var lostPhoneChannel: MethodChannel? = null
    private var volumeInterceptionEnabled = false

    private var isVolumeUpPressed = false
    private var isVolumeDownPressed = false
    private var bothPressedTriggered = false
    private var longPressTriggered = false

    private val mainHandler = Handler(Looper.getMainLooper())
    private var longPressRunnable: Runnable? = null

    // Tolerances for clean hardware button navigation and confirmation
    private val LONG_PRESS_MS = 600L
    private val DEBOUNCE_MS = 200L
    private var lastNavTimeMs = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "enableVolumeInterception" -> {
                        volumeInterceptionEnabled = true
                        resetKeyState()
                        result.success(true)
                    }
                    "disableVolumeInterception" -> {
                        volumeInterceptionEnabled = false
                        resetKeyState()
                        result.success(true)
                    }
                    "isVolumeInterceptionEnabled" -> {
                        result.success(volumeInterceptionEnabled)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        lostPhoneChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOST_PHONE_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "startLostPhoneMode" -> {
                        val timeout = call.argument<Int>("timeoutMinutes") ?: 20
                        val intent = Intent(this@MainActivity, LostPhoneService::class.java).apply {
                            action = LostPhoneService.ACTION_START
                            putExtra(LostPhoneService.EXTRA_TIMEOUT_MINUTES, timeout)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    }
                    "stopLostPhoneMode" -> {
                        val intent = Intent(this@MainActivity, LostPhoneService::class.java).apply {
                            action = LostPhoneService.ACTION_STOP
                        }
                        startService(intent)
                        result.success(true)
                    }
                    "stopAlarm" -> {
                        val intent = Intent(this@MainActivity, LostPhoneService::class.java).apply {
                            action = LostPhoneService.ACTION_STOP_ALARM
                        }
                        startService(intent)
                        result.success(true)
                    }
                    "testAlarm" -> {
                        val intent = Intent(this@MainActivity, LostPhoneService::class.java).apply {
                            action = LostPhoneService.ACTION_TEST_ALARM
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    }
                    "isServiceRunning" -> {
                        result.success(LostPhoneService.isRunning)
                    }
                    "isAlarmRinging" -> {
                        result.success(LostPhoneService.isAlarmRinging)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        LostPhoneService.eventListener = object : LostPhoneService.LostPhoneListener {
            override fun onServiceStateChanged(running: Boolean) {
                mainHandler.post {
                    lostPhoneChannel?.invokeMethod("onServiceStateChanged", mapOf("isRunning" to running))
                }
            }

            override fun onAlarmTriggered(phrase: String) {
                mainHandler.post {
                    lostPhoneChannel?.invokeMethod("onAlarmTriggered", mapOf("phrase" to phrase))
                }
            }

            override fun onAlarmStopped() {
                mainHandler.post {
                    lostPhoneChannel?.invokeMethod("onAlarmStopped", emptyMap<String, Any>())
                }
            }

            override fun onIrisWakeup(phrase: String) {
                mainHandler.post {
                    lostPhoneChannel?.invokeMethod("onIrisWakeup", mapOf("phrase" to phrase))
                }
            }

            override fun onVoiceCommand(command: String) {
                mainHandler.post {
                    lostPhoneChannel?.invokeMethod("onVoiceCommand", mapOf("command" to command))
                }
            }

            override fun onServiceError(error: String) {
                mainHandler.post {
                    lostPhoneChannel?.invokeMethod("onServiceError", mapOf("error" to error))
                }
            }
        }

        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        if (intent.getBooleanExtra("from_lost_phone_alarm", false)) {
            val phrase = intent.getStringExtra("triggered_phrase") ?: "Hey Iris"
            mainHandler.post {
                lostPhoneChannel?.invokeMethod("onAlarmTriggered", mapOf("phrase" to phrase))
            }
        }
        if (intent.getBooleanExtra("from_iris_wakeup", false)) {
            val phrase = intent.getStringExtra("phrase") ?: "Hey Iris"
            val command = intent.getStringExtra("command") ?: ""
            mainHandler.post {
                lostPhoneChannel?.invokeMethod("onIrisWakeup", mapOf("phrase" to phrase))
                if (command.isNotEmpty()) {
                    lostPhoneChannel?.invokeMethod("onVoiceCommand", mapOf("command" to command))
                }
            }
        }
        if (intent.getBooleanExtra("from_voice_command", false)) {
            val command = intent.getStringExtra("command") ?: ""
            if (command.isNotEmpty()) {
                mainHandler.post {
                    lostPhoneChannel?.invokeMethod("onVoiceCommand", mapOf("command" to command))
                }
            }
        }
    }

    private fun resetKeyState() {
        isVolumeUpPressed = false
        isVolumeDownPressed = false
        bothPressedTriggered = false
        longPressTriggered = false
        longPressRunnable?.let { mainHandler.removeCallbacks(it) }
        longPressRunnable = null
        lastNavTimeMs = 0L
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        // Blind user accessibility: When the alarm is sounding, pressing ANY hardware button
        // (Volume Up, Volume Down, Power) immediately silences the alarm.
        if (LostPhoneService.isAlarmRinging && event.action == KeyEvent.ACTION_DOWN) {
            val intent = Intent(this, LostPhoneService::class.java).apply {
                action = LostPhoneService.ACTION_STOP_ALARM
            }
            startService(intent)
            return true
        }

        val keyCode = event.keyCode

        // Detect Power button to confirm if Android delivers it to our window
        if (keyCode == KeyEvent.KEYCODE_POWER) {
            if (volumeInterceptionEnabled && event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                sendEventToFlutter("confirm", "power_button")
                return true
            }
            return super.dispatchKeyEvent(event)
        }

        // If volume interception is disabled, allow normal OS volume control
        if (!volumeInterceptionEnabled) {
            return super.dispatchKeyEvent(event)
        }

        if (keyCode != KeyEvent.KEYCODE_VOLUME_UP && keyCode != KeyEvent.KEYCODE_VOLUME_DOWN) {
            return super.dispatchKeyEvent(event)
        }

        when (event.action) {
            KeyEvent.ACTION_DOWN -> {
                // Ignore key repeats to strictly prevent accidental repeated navigation on long presses
                if (event.repeatCount > 0) {
                    return true
                }

                if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
                    isVolumeUpPressed = true
                } else if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
                    isVolumeDownPressed = true
                }

                // Check if BOTH are pressed simultaneously (chorded confirm)
                if (isVolumeUpPressed && isVolumeDownPressed) {
                    longPressRunnable?.let { mainHandler.removeCallbacks(it) }
                    longPressRunnable = null
                    bothPressedTriggered = true
                    sendEventToFlutter("confirm", "both_volume_keys")
                    return true
                }

                // Schedule long press confirmation (accessible alternative without navigating first)
                longPressTriggered = false
                longPressRunnable?.let { mainHandler.removeCallbacks(it) }
                longPressRunnable = Runnable {
                    if ((isVolumeUpPressed || isVolumeDownPressed) && !bothPressedTriggered) {
                        longPressTriggered = true
                        sendEventToFlutter("confirm", "volume_long_press")
                    }
                }
                mainHandler.postDelayed(longPressRunnable!!, LONG_PRESS_MS)

                return true
            }

            KeyEvent.ACTION_UP -> {
                longPressRunnable?.let { mainHandler.removeCallbacks(it) }
                longPressRunnable = null

                val wasChord = bothPressedTriggered
                val wasLongPress = longPressTriggered

                if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
                    isVolumeUpPressed = false
                } else if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
                    isVolumeDownPressed = false
                }

                if (!isVolumeUpPressed && !isVolumeDownPressed) {
                    bothPressedTriggered = false
                    longPressTriggered = false
                }

                // If this release was from a chord or long-press confirmation, suppress navigation
                if (wasChord || wasLongPress) {
                    return true
                }

                // Enforce debounce to prevent bounce/jitter
                val now = android.os.SystemClock.uptimeMillis()
                if (now - lastNavTimeMs < DEBOUNCE_MS) {
                    return true
                }
                lastNavTimeMs = now

                // Single intentional click navigation: Volume Up = next, Volume Down = previous
                if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
                    sendEventToFlutter("volume_up", "single_press")
                } else if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
                    sendEventToFlutter("volume_down", "single_press")
                }

                return true
            }
        }

        return true
    }

    private fun sendEventToFlutter(event: String, detail: String) {
        mainHandler.post {
            methodChannel?.invokeMethod(
                "onVolumeKeyEvent",
                mapOf("event" to event, "detail" to detail)
            )
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    override fun onDestroy() {
        LostPhoneService.eventListener = null
        resetKeyState()
        super.onDestroy()
    }
}
