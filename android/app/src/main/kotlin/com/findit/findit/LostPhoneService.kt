package com.findit.findit

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import java.util.Locale

class LostPhoneService : Service() {

    companion object {
        private const val TAG = "LostPhoneService"
        const val CHANNEL_ID = "findit_lost_phone_channel"
        const val NOTIFICATION_ID = 9021

        const val ACTION_START = "com.findit.findit.ACTION_START_LOST_PHONE"
        const val ACTION_STOP = "com.findit.findit.ACTION_STOP_LOST_PHONE"
        const val ACTION_STOP_ALARM = "com.findit.findit.ACTION_STOP_ALARM"
        const val ACTION_TEST_ALARM = "com.findit.findit.ACTION_TEST_ALARM"

        const val EXTRA_TIMEOUT_MINUTES = "extra_timeout_minutes"

        @Volatile
        var isRunning: Boolean = false
            private set

        @Volatile
        var isAlarmRinging: Boolean = false
            private set

        var eventListener: LostPhoneListener? = null
    }

    interface LostPhoneListener {
        fun onServiceStateChanged(running: Boolean)
        fun onAlarmTriggered(phrase: String)
        fun onAlarmStopped()
        fun onIrisWakeup(phrase: String)
        fun onVoiceCommand(command: String)
        fun onServiceError(error: String)
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var speechRecognizer: SpeechRecognizer? = null
    private var mediaPlayer: MediaPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var batteryReceiver: BroadcastReceiver? = null

    private var timeoutMinutes: Int = 20
    private var isRecognizing: Boolean = false
    private var consecutiveErrors: Int = 0

    // 1. Alarm Trigger: ONLY when the user explicitly asks where the phone is or to ring the phone
    private val alarmTriggerRegex = Regex(
        """(?i)\bwhere\s+are\s+you\b|""" +
        """(?i)\b(find|ring|locate|where\s+is)\s*(my\s+|the\s+)?phone\b|""" +
        """(?i)\bphone\s*(ring|where)\b|""" +
        """\b(कहाँ\s+हो|कहा\s+हो|फोन\s+कहाँ\s+है|फोन\s+ढूंढो|फोन\s+बजाओ|खोया\s+फोन)\b|""" +
        """\b(ಫೋನ್\s+ಎಲ್ಲಿದೆ|ಎಲ್ಲಿದ್ದೀಯಾ?|ಫೋನ್\s+ರಿಂಗ್\s+ಮಾಡು|ಕಳೆದುಹೋದ\s+ಫೋನ್)\b"""
    )

    // 2. Assistant Wakeup: "Hey Iris", "Iris", "Hi Iris", "Ok Iris", phonetic matches like "Here it is" / "Here is", "Harris", "Harry", "हे आइरिस", "ಐರಿಸ್"
    private val irisWakeupRegex = Regex(
        """(?i)\b(hey|hi|ok|okay|hei|hai|ay|a|here|hay)?\s*(iris|irish|ayres|aires|ayris|airis|eris|irus|iras|ires|aris|iriss|it\s+is)\b|""" +
        """(?i)\bhere\s+is\b|\bharris\b|\bharry\b|\bheiress\b|\bhigh\s*risk\b|""" +
        """(हे|हाय|हेलो\s+)?(आइरिस|आयरिस|आईरिस|इरिस)|(ಹೇ|ಹಾಯ್\s+)?(ಐರಿಸ್)"""
    )

    // 3. Stop Alarm: Voice commands to silence ringing alarm
    private val stopAlarmRegex = Regex(
        """(?i)\b(stop(\s+(the|this))?\s*alarm|stop\s*(it|this|please|now)?|alarm\s*stop|silence(\s*alarm)?|quiet|shut\s*up|cancel|mute(\s*alarm)?|turn\s*off(\s+(the|this))?\s*alarm|off(\s+(the|this))?\s*alarm|found(\s*(it|my\s*phone|the\s*phone))?|i\s*found\s*(it|my\s*phone)|got\s*it|i\s*got\s*it|phone\s*found)\b|""" +
        """(?i)\b(hey\s+|hi\s+|ok\s+|okay\s+)?(iris|irish|ayres|aires|eris|here\s+is)\s+(stop|top|talk|quiet|silence|cancel|off|close)\b|""" +
        """\b(अलार्म\s*(बंद\s*(करो|कर\s*दो)?|रोको?)|बंद\s*(करो|कर\s*दो)|फोन\s*मिल\s*गया|मिल\s*गया|चुप\s*(हो\s*जाओ|रहो)?|रुको|आवाज\s*बंद\s*(करो)?)\b|""" +
        """\b(ಅಲಾರಂ\s*ನಿಲ್ಲಿಸು|ನಿಲ್ಲಿಸು|ಆಫ್\s*ಮಾಡು|ಫೋನ್\s*ಸಿಕ್ತು|ಸಾಕು)\b"""
    )

    private var isAwaitingUserCommand: Boolean = false
    private var isSpeakingPrompt: Boolean = false
    private val commandTimeoutRunnable = Runnable {
        Log.i(TAG, "Command response window timed out. Resuming normal hotword listening.")
        isAwaitingUserCommand = false
        isSpeakingPrompt = false
        startSpeechRecognizer()
    }

    private var textToSpeech: TextToSpeech? = null
    private var isTtsReady: Boolean = false

    private fun initTextToSpeech() {
        try {
            textToSpeech = TextToSpeech(applicationContext) { status ->
                if (status == TextToSpeech.SUCCESS) {
                    isTtsReady = true
                    Log.i(TAG, "Native TextToSpeech initialized successfully.")
                    val locale = getPreferredLocale()
                    try {
                        val setLangRes = textToSpeech?.setLanguage(locale)
                        Log.i(TAG, "TTS setLanguage($locale) = $setLangRes")
                    } catch (e: Exception) {
                        Log.w(TAG, "TTS setLanguage error: ${e.message}")
                    }
                    textToSpeech?.setSpeechRate(0.95f)
                    textToSpeech?.setPitch(1.0f)
                    try {
                        val audioAttrs = AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build()
                        textToSpeech?.setAudioAttributes(audioAttrs)
                    } catch (_: Exception) {}

                    textToSpeech?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                        override fun onStart(utteranceId: String?) {
                            Log.i(TAG, "TTS onStart: $utteranceId")
                        }

                        override fun onDone(utteranceId: String?) {
                            Log.i(TAG, "TTS onDone: $utteranceId")
                            if (utteranceId == "iris_wakeup_prompt") {
                                // 350ms pause allows speaker acoustic reverberation to clear before mic opens
                                mainHandler.postDelayed({
                                    isSpeakingPrompt = false
                                    isAwaitingUserCommand = true
                                    mainHandler.removeCallbacks(commandTimeoutRunnable)
                                    mainHandler.postDelayed(commandTimeoutRunnable, 10000L)
                                    startSpeechRecognizer()
                                }, 350L)
                            }
                        }

                        override fun onError(utteranceId: String?) {
                            Log.w(TAG, "TTS onError: $utteranceId")
                            if (utteranceId == "iris_wakeup_prompt") {
                                mainHandler.postDelayed({
                                    isSpeakingPrompt = false
                                    isAwaitingUserCommand = true
                                    mainHandler.removeCallbacks(commandTimeoutRunnable)
                                    mainHandler.postDelayed(commandTimeoutRunnable, 10000L)
                                    startSpeechRecognizer()
                                }, 350L)
                            }
                        }
                    })
                } else {
                    Log.e(TAG, "Native TTS initialization failed with status: $status")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "initTextToSpeech error: ${e.message}")
        }
    }

    private fun getPreferredLocale(): Locale {
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val langCode = prefs.getString("flutter.findit_preferred_language", "en") ?: "en"
            return when (langCode.lowercase()) {
                "hi", "hin", "hindi" -> Locale("hi", "IN")
                "kn", "kan", "kannada" -> Locale("kn", "IN")
                "te", "tel", "telugu" -> Locale("te", "IN")
                "ta", "tam", "tamil" -> Locale("ta", "IN")
                else -> Locale.ENGLISH
            }
        } catch (_: Exception) {
            return Locale.ENGLISH
        }
    }

    private fun getHowCanIHelpPrompt(): Pair<String, Locale> {
        val locale = getPreferredLocale()
        val text = when (locale.language) {
            "hi" -> "मैं आपकी क्या मदद करूँ?"
            "kn" -> "ನಾನು ನಿಮಗೆ ಹೇಗೆ ಸಹಾಯ ಮಾಡಲಿ?"
            "te" -> "నేను మీకు ఎలా సహాయం చేయగలను?"
            "ta" -> "நான் உங்களுக்கு எவ்வாறு உதவ முடியும்?"
            else -> "How can I help you?"
        }
        return Pair(text, locale)
    }

    private fun speakHowCanIHelpAndListen() {
        val (prompt, locale) = getHowCanIHelpPrompt()
        Log.i(TAG, "Speaking prompt: '$prompt' in locale: $locale")

        // Unmute and elevate media stream volume if low so blind user clearly hears it
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            val currentVol = audioManager?.getStreamVolume(AudioManager.STREAM_MUSIC) ?: 0
            val maxVol = audioManager?.getStreamMaxVolume(AudioManager.STREAM_MUSIC) ?: 15
            if (currentVol < maxVol / 2) {
                audioManager?.setStreamVolume(AudioManager.STREAM_MUSIC, (maxVol * 0.75).toInt(), 0)
            }
        } catch (_: Exception) {}

        isSpeakingPrompt = true
        mainHandler.removeCallbacks(restartRunnable)

        if (textToSpeech != null && isTtsReady) {
            try {
                textToSpeech?.language = locale
                val params = Bundle().apply {
                    putInt(TextToSpeech.Engine.KEY_PARAM_STREAM, AudioManager.STREAM_MUSIC)
                    putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 1.0f)
                }
                val res = textToSpeech?.speak(prompt, TextToSpeech.QUEUE_FLUSH, params, "iris_wakeup_prompt")
                Log.i(TAG, "TTS speak result: $res")
                if (res == TextToSpeech.SUCCESS) {
                    return
                }
            } catch (e: Exception) {
                Log.e(TAG, "TTS speak failed: ${e.message}")
            }
        }

        // Fallback if TTS engine wasn't ready: pause 1.8s then start listening for reply
        mainHandler.postDelayed({
            isSpeakingPrompt = false
            isAwaitingUserCommand = true
            mainHandler.removeCallbacks(commandTimeoutRunnable)
            mainHandler.postDelayed(commandTimeoutRunnable, 10000L)
            startSpeechRecognizer()
        }, 1800L)
    }

    private val restartRunnable = Runnable {
        if (isRunning) {
            startSpeechRecognizer()
        }
    }

    private val serviceAutoStopRunnable = Runnable {
        Log.i(TAG, "Lost Phone Mode reached auto-timeout ($timeoutMinutes min) to conserve battery.")
        eventListener?.onServiceError("Lost Phone Mode auto-stopped after $timeoutMinutes min to save battery.")
        stopSelf()
    }

    private val alarmAutoStopRunnable = Runnable {
        Log.i(TAG, "Alarm reached 3-minute auto-silence safety limit.")
        stopAlarm()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        registerBatteryMonitor()
        initTextToSpeech()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START

        when (action) {
            ACTION_STOP -> {
                stopAlarm()
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_STOP_ALARM -> {
                stopAlarm()
                return START_STICKY
            }
            ACTION_TEST_ALARM -> {
                triggerAlarm("Test Alarm")
                return START_STICKY
            }
            ACTION_START -> {
                timeoutMinutes = intent?.getIntExtra(EXTRA_TIMEOUT_MINUTES, 20)?.coerceIn(5, 60) ?: 20
                startForegroundServiceMode()
                return START_STICKY
            }
        }

        return START_NOT_STICKY
    }

    private fun startForegroundServiceMode() {
        if (isRunning) {
            return
        }
        isRunning = true
        eventListener?.onServiceStateChanged(true)

        // 1. Acquire partial wake lock to keep CPU active during detection window
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "FindIt:LostPhoneWakeLock"
            ).apply {
                acquire(timeoutMinutes * 60 * 1000L)
            }
        } catch (e: Exception) {
            Log.e(TAG, "WakeLock acquire failed: ${e.message}")
        }

        // 2. Start Foreground Service with microphone type on Android 10+
        val notification = buildListeningNotification()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            Log.e(TAG, "startForeground failed: ${e.message}")
            eventListener?.onServiceError("Could not start foreground microphone service: ${e.message}")
            stopSelf()
            return
        }

        // 3. Schedule auto-timeout to prevent indefinite battery drain
        mainHandler.removeCallbacks(serviceAutoStopRunnable)
        mainHandler.postDelayed(serviceAutoStopRunnable, timeoutMinutes * 60 * 1000L)

        // 4. Start hotword recognition
        startSpeechRecognizer()
    }

    private fun resetSpeechRecognizer() {
        try {
            speechRecognizer?.cancel()
            speechRecognizer?.destroy()
        } catch (_: Exception) {}
        speechRecognizer = null
        isRecognizing = false
    }

    private fun startSpeechRecognizer() {
        mainHandler.post {
            if (!isRunning || isSpeakingPrompt) return@post
            try {
                if (speechRecognizer == null) {
                    if (!SpeechRecognizer.isRecognitionAvailable(this)) {
                        Log.e(TAG, "Android SpeechRecognizer is unavailable on this device.")
                        eventListener?.onServiceError("Android SpeechRecognizer is unavailable on this device.")
                        return@post
                    }
                    speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this).apply {
                        setRecognitionListener(speechListener)
                    }
                }

                // Always cancel previous session before starting a new listening pass
                try {
                    speechRecognizer?.cancel()
                } catch (_: Exception) {}

                val locale = getPreferredLocale()
                val langTag = when (locale.language) {
                    "hi" -> "hi-IN"
                    "kn" -> "kn-IN"
                    "te" -> "te-IN"
                    "ta" -> "ta-IN"
                    else -> "en-IN"
                }

                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, langTag)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, langTag)
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 10)
                    putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
                    if (isAlarmRinging) {
                        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 500L)
                        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 600L)
                        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 600L)
                    } else {
                        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 500L)
                        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 800L)
                        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 800L)
                    }
                }
                isRecognizing = true
                speechRecognizer?.startListening(intent)
                Log.i(TAG, "SpeechRecognizer started listening (lang=$langTag, awaitingReply=$isAwaitingUserCommand)")
            } catch (e: Exception) {
                Log.e(TAG, "startSpeechRecognizer error: ${e.message}")
                resetSpeechRecognizer()
                scheduleRestart(1000)
            }
        }
    }

    private val speechListener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {
            isRecognizing = true
            consecutiveErrors = 0
            Log.i(TAG, "Ready for speech (awaitingCommand=$isAwaitingUserCommand)")
        }

        override fun onBeginningOfSpeech() {
            Log.i(TAG, "Beginning of speech detected")
        }

        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}

        override fun onEndOfSpeech() {
            isRecognizing = false
            Log.i(TAG, "End of speech detected")
        }

        override fun onError(error: Int) {
            isRecognizing = false
            Log.w(TAG, "SpeechRecognizer onError: $error (awaitingCommand=$isAwaitingUserCommand)")
            if (!isRunning || isSpeakingPrompt) return

            // Errors 6 (SPEECH_TIMEOUT) and 7 (NO_MATCH) are expected in silence
            val delayMs = when (error) {
                SpeechRecognizer.ERROR_NO_MATCH,
                SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> 250L
                SpeechRecognizer.ERROR_RECOGNIZER_BUSY,
                SpeechRecognizer.ERROR_CLIENT -> {
                    consecutiveErrors++
                    resetSpeechRecognizer()
                    500L
                }
                SpeechRecognizer.ERROR_AUDIO,
                SpeechRecognizer.ERROR_SERVER,
                SpeechRecognizer.ERROR_NETWORK -> {
                    consecutiveErrors++
                    if (consecutiveErrors > 2) {
                        resetSpeechRecognizer()
                        1500L
                    } else {
                        500L
                    }
                }
                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> {
                    eventListener?.onServiceError("Microphone permission missing for Lost Phone Mode.")
                    stopSelf()
                    return
                }
                else -> {
                    resetSpeechRecognizer()
                    500L
                }
            }
            scheduleRestart(delayMs)
        }

        override fun onResults(results: Bundle?) {
            isRecognizing = false
            if (!isRunning || isSpeakingPrompt) return
            val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            if (!checkMatches(matches, isPartial = false)) {
                scheduleRestart(250)
            }
        }

        override fun onPartialResults(partialResults: Bundle?) {
            if (!isRunning || isSpeakingPrompt) return
            val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            checkMatches(matches, isPartial = true)
        }

        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    private fun stripIrisHotword(phrase: String): String {
        return phrase
            .replace(Regex("""(?i)^\s*(hey|hi|ok|okay|hei|hai|ay|a|here|hay)?\s*(iris|irish|ayres|aires|ayris|airis|eris|irus|iras|ires|aris|iriss|it\s+is)\b[:,\s]*"""), "")
            .replace(Regex("""(?i)^\s*here\s+is\b[:,\s]*"""), "")
            .replace(Regex("""(?i)^\s*harris\b[:,\s]*"""), "")
            .replace(Regex("""(?i)^\s*harry\b[:,\s]*"""), "")
            .replace(Regex("""(?i)^\s*heiress\b[:,\s]*"""), "")
            .replace(Regex("""(?i)^\s*high\s*risk\b[:,\s]*"""), "")
            .replace(Regex("""^\s*(हे|हाय|हेलो\s+)?(आइरिस|आयरिस|आईरिस|इरिस)\b[:,\s]*"""), "")
            .replace(Regex("""^\s*(ಹೇ|ಹಾಯ್\s+)?(ಐರಿಸ್)\b[:,\s]*"""), "")
            .trim()
    }

    private fun handleIrisWakeup(phrase: String) {
        Log.i(TAG, "Iris wakeup detected: '$phrase'")

        val cleanedCommand = stripIrisHotword(phrase)
        val hasDirectCommand = cleanedCommand.isNotEmpty() && cleanedCommand.length >= 3

        // Bring MainActivity to foreground
        try {
            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("from_iris_wakeup", true)
                putExtra("phrase", phrase)
                putExtra("command", if (hasDirectCommand) cleanedCommand else "")
            }
            if (launchIntent != null) {
                startActivity(launchIntent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Launch activity error: ${e.message}")
        }

        // 1. Immediately cancel the current speech recognizer pass and mark prompt speaking
        isSpeakingPrompt = true
        mainHandler.removeCallbacks(restartRunnable)
        try {
            speechRecognizer?.cancel()
            isRecognizing = false
        } catch (_: Exception) {}

        if (hasDirectCommand) {
            Log.i(TAG, "Direct command detected with hotword: '$cleanedCommand'")
            isSpeakingPrompt = false
            isAwaitingUserCommand = false
            eventListener?.onVoiceCommand(cleanedCommand)
            scheduleRestart(1500)
        } else {
            // User said "Hey Iris" only -> speak "How can I help you?" via TTS out loud!
            eventListener?.onIrisWakeup(phrase)
            speakHowCanIHelpAndListen()
        }
    }

    private fun checkMatches(matches: ArrayList<String>?, isPartial: Boolean): Boolean {
        if (matches == null || matches.isEmpty()) return false
        for (phrase in matches) {
            val clean = phrase.trim()
            Log.i(TAG, "Speech candidate (partial=$isPartial, awaitingReply=$isAwaitingUserCommand): '$clean'")

            if (isAlarmRinging) {
                if (stopAlarmRegex.containsMatchIn(clean)) {
                    Log.i(TAG, "Stop alarm command matched: '$clean'")
                    stopAlarm()
                    return true
                }
            } else if (isAwaitingUserCommand) {
                // IMPORTANT: Never consume replies on partial results! Wait for full utterance onResults
                if (!isPartial) {
                    Log.i(TAG, "User command final reply candidate: '$clean'")
                    if (alarmTriggerRegex.containsMatchIn(clean)) {
                        isAwaitingUserCommand = false
                        mainHandler.removeCallbacks(commandTimeoutRunnable)
                        Log.i(TAG, "Alarm trigger matched in reply: '$clean'")
                        triggerAlarm(clean)
                        return true
                    }
                    val cmd = stripIrisHotword(clean)
                    // Ensure candidate is NOT just a repeated "Hey Iris"
                    if (cmd.isNotEmpty() && cmd.length >= 2 && !irisWakeupRegex.matches(clean)) {
                        isAwaitingUserCommand = false
                        mainHandler.removeCallbacks(commandTimeoutRunnable)
                        Log.i(TAG, "Voice command received in reply: '$cmd'")

                        // Bring MainActivity to foreground
                        try {
                            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                                putExtra("from_voice_command", true)
                                putExtra("command", cmd)
                            }
                            if (launchIntent != null) {
                                startActivity(launchIntent)
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Launch activity on voice command error: ${e.message}")
                        }

                        eventListener?.onVoiceCommand(cmd)
                        scheduleRestart(1500)
                        return true
                    }
                }
            } else {
                if (alarmTriggerRegex.containsMatchIn(clean)) {
                    Log.i(TAG, "Alarm trigger matched by candidate: '$clean'")
                    triggerAlarm(clean)
                    return true
                } else if (irisWakeupRegex.containsMatchIn(clean)) {
                    Log.i(TAG, "Iris hotword detected by candidate: '$clean'")
                    handleIrisWakeup(clean)
                    return true
                }
            }
        }
        return false
    }

    private fun scheduleRestart(delayMs: Long) {
        mainHandler.removeCallbacks(restartRunnable)
        if (isRunning && !isSpeakingPrompt) {
            mainHandler.postDelayed(restartRunnable, delayMs)
        }
    }

    private fun triggerAlarm(phrase: String) {
        if (isAlarmRinging) return
        isAlarmRinging = true

        // 1. Stop speech listener briefly for audio initialization
        try {
            speechRecognizer?.stopListening()
            speechRecognizer?.cancel()
            isRecognizing = false
        } catch (_: Exception) {}

        // 2. Maximize alarm stream volume
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
            audioManager.setStreamVolume(AudioManager.STREAM_ALARM, maxVol, 0)
        } catch (e: Exception) {
            Log.e(TAG, "Volume set error: ${e.message}")
        }

        // 3. Play loud alarm ringtone
        try {
            val alertUri: Uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

            mediaPlayer?.release()
            mediaPlayer = MediaPlayer().apply {
                setDataSource(applicationContext, alertUri)
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                isLooping = true
                prepare()
                start()
            }
        } catch (e: Exception) {
            Log.e(TAG, "MediaPlayer error: ${e.message}")
        }

        // 4. Vibrate in heavy SOS cadence
        try {
            val vibrator = getVibrator()
            val pattern = longArrayOf(0, 600, 200, 600, 200, 1000)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(pattern, 0)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Vibrator error: ${e.message}")
        }

        // 5. Update notification to high priority alarm banner
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.notify(NOTIFICATION_ID, buildAlarmNotification(phrase))
        } catch (e: Exception) {
            Log.e(TAG, "Notification update error: ${e.message}")
        }

        // 6. Bring MainActivity to foreground
        try {
            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("from_lost_phone_alarm", true)
                putExtra("triggered_phrase", phrase)
            }
            if (launchIntent != null) {
                startActivity(launchIntent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Launch activity error: ${e.message}")
        }

        // 7. Notify listeners
        eventListener?.onAlarmTriggered(phrase)

        // 8. 3-minute safety timeout to auto-stop ringing
        mainHandler.removeCallbacks(alarmAutoStopRunnable)
        mainHandler.postDelayed(alarmAutoStopRunnable, 3 * 60 * 1000L)

        // 9. Schedule speech listener to listen for "Stop" command after audio initializes
        scheduleRestart(600)
    }

    fun stopAlarm() {
        if (!isAlarmRinging) return
        isAlarmRinging = false
        mainHandler.removeCallbacks(alarmAutoStopRunnable)

        // Cancel active recognizer pass so "stop" is not interpreted as next hotword
        try {
            speechRecognizer?.stopListening()
            speechRecognizer?.cancel()
            isRecognizing = false
        } catch (_: Exception) {}

        try {
            mediaPlayer?.stop()
            mediaPlayer?.release()
            mediaPlayer = null
        } catch (_: Exception) {}

        try {
            getVibrator()?.cancel()
        } catch (_: Exception) {}

        if (isRunning) {
            try {
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.notify(NOTIFICATION_ID, buildListeningNotification())
            } catch (_: Exception) {}
            scheduleRestart(500)
        }

        eventListener?.onAlarmStopped()
    }

    private fun getVibrator(): Vibrator? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vm = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            vm?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Lost Phone Mode",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "FindIt microphone service listening for 'Hey Iris'"
                setShowBadge(true)
            }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun buildListeningNotification(): Notification {
        val openIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingOpen = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(this, LostPhoneService::class.java).apply {
            action = ACTION_STOP
        }
        val pendingStop = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder.setContentTitle("FindIt: Lost Phone Mode Active")
            .setContentText("Listening for \"Hey Iris\" (auto-off in $timeoutMinutes min)...")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentIntent(pendingOpen)
            .setOngoing(true)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "STOP", pendingStop)

        return builder.build()
    }

    private fun buildAlarmNotification(phrase: String): Notification {
        val openIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("from_lost_phone_alarm", true)
        }
        val pendingOpen = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val silenceIntent = Intent(this, LostPhoneService::class.java).apply {
            action = ACTION_STOP_ALARM
        }
        val pendingSilence = PendingIntent.getService(
            this,
            2,
            silenceIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder.setContentTitle("🚨 PHONE FOUND! ALARM RINGING 🚨")
            .setContentText("Heard: \"$phrase\". Tap below to silence.")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentIntent(pendingOpen)
            .setOngoing(true)
            .addAction(android.R.drawable.ic_lock_silent_mode_off, "SILENCE ALARM", pendingSilence)

        return builder.build()
    }

    private fun registerBatteryMonitor() {
        batteryReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (Intent.ACTION_BATTERY_LOW == intent?.action) {
                    Log.w(TAG, "Battery low detected (<15%). Auto-stopping Lost Phone Mode.")
                    eventListener?.onServiceError("Lost Phone Mode auto-stopped: Device battery is low (<15%).")
                    stopSelf()
                }
            }
        }
        val filter = IntentFilter(Intent.ACTION_BATTERY_LOW)
        registerReceiver(batteryReceiver, filter)
    }

    override fun onDestroy() {
        isRunning = false
        isAlarmRinging = false
        isSpeakingPrompt = false
        isAwaitingUserCommand = false
        mainHandler.removeCallbacksAndMessages(null)

        stopAlarm()

        try {
            speechRecognizer?.destroy()
            speechRecognizer = null
        } catch (_: Exception) {}

        try {
            textToSpeech?.stop()
            textToSpeech?.shutdown()
            textToSpeech = null
            isTtsReady = false
        } catch (_: Exception) {}

        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Exception) {}

        try {
            if (batteryReceiver != null) {
                unregisterReceiver(batteryReceiver)
                batteryReceiver = null
            }
        } catch (_: Exception) {}

        eventListener?.onServiceStateChanged(false)
        super.onDestroy()
    }
}
