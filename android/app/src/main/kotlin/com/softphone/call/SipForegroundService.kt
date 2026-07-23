package com.softphone.call

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import org.linphone.core.*

class SipForegroundService : Service() {

    companion object {
        private const val NOTIFICATION_ID        = 1001
        private const val CALL_NOTIFICATION_ID   = 1002
        private const val MISSED_NOTIFICATION_ID = 1003
        private const val CHANNEL_ID             = "sip_foreground_channel"
        private const val CALL_CHANNEL_ID        = "sip_incoming_call_channel"
        private const val MISSED_CHANNEL_ID      = "sip_missed_call_channel"
        private const val PREFS_NAME             = "sip_prefs"

        const val ACTION_ACCEPT  = "com.softphone.call.ACTION_ACCEPT"
        const val ACTION_DECLINE = "com.softphone.call.ACTION_DECLINE"
        const val PREFS_PENDING_LOGS = "pending_call_logs"

        /** True while MainActivity (Flutter engine) is alive */
        @Volatile var isFlutterEngineActive: Boolean = false

        /** Static Core instance shared with MainActivity */
        @Volatile var core: Core? = null
            private set

        /**
         * The CoreListener most recently attached by a MainActivity/Flutter-engine
         * instance. MainActivity replaces this (removing the old one first) every
         * time its engine is (re)configured, so events are only ever forwarded to
         * Dart once per call state change - without this, every engine recreation
         * (e.g. opening the app from the incoming-call full-screen intent while it
         * was killed) stacked another listener on this same long-lived Core,
         * causing duplicate INCOMING events, orphaned CallKit entries, and spurious
         * missed-call notifications even for calls that were actually answered.
         */
        @Volatile var activityListener: CoreListenerStub? = null

        /**
         * Set by CallActionReceiver right before declining a ringing call.
         * The instance-level callWasAnswered flag only distinguishes
         * "answered" from "not answered", which also covers an explicit
         * decline - without this, declining a call showed a "missed call"
         * notification for a call the user had just actively rejected.
         * CallActionReceiver is a plain nested class (no outer-instance
         * reference), so this has to live on the companion object rather
         * than as an instance field.
         */
        @Volatile var wasDeclinedByUser: Boolean = false

        /**
         * The service-level CoreListener (notifications, missed-call
         * tracking, pending call log saving). initCore() re-attaches this
         * every time onCreate() runs against an already-existing Core (e.g.
         * after onDestroy()'s auto-restart, if Android recreated the
         * Service without killing the whole process) - without removing
         * the previous one first, that stacked duplicate service-level
         * listeners the same way activityListener did for MainActivity.
         */
        @Volatile var serviceListener: CoreListenerStub? = null

        fun saveCredentials(
            context: Context,
            domain: String, username: String, password: String, transport: String
        ) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
                .putString("domain", domain)
                .putString("username", username)
                .putString("password", password)
                .putString("transport", transport)
                .apply()
        }

        fun clearCredentials(context: Context) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit().clear().apply()
        }

        fun start(context: Context) {
            context.startForegroundService(Intent(context, SipForegroundService::class.java))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, SipForegroundService::class.java))
        }
    }

    // -----------------------------------------------------------------------
    // BroadcastReceiver for Accept / Decline button taps on the notification
    // -----------------------------------------------------------------------
    class CallActionReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val c = core
            // core.currentCall is only set once a call's media is running,
            // so it's null for a still-ringing incoming call - look up the
            // actual ringing call explicitly instead.
            val ringingCall = c?.calls?.find { it.state == Call.State.IncomingReceived }
            when (intent.action) {
                ACTION_ACCEPT -> {
                    ringingCall?.accept()
                    val open = Intent(context, MainActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                        putExtra("action", "answer")
                    }
                    context.startActivity(open)
                }
                ACTION_DECLINE -> {
                    wasDeclinedByUser = true
                    val incoming = c?.calls?.find {
                        it.dir == Call.Dir.Incoming &&
                        it.state != Call.State.Connected &&
                        it.state != Call.State.StreamsRunning
                    }
                    if (incoming != null) {
                        try {
                            incoming.accept()
                        } catch (e: Exception) {
                            e.printStackTrace()
                        }
                        incoming.terminate()
                    } else if (c?.currentCall != null) {
                        c.currentCall?.terminate()
                    } else {
                        c?.terminateAllCalls()
                    }
                    val nm = context.getSystemService(NotificationManager::class.java)
                    nm.cancel(CALL_NOTIFICATION_ID)
                }
            }
        }
    }

    // -----------------------------------------------------------------------
    // Service lifecycle
    // -----------------------------------------------------------------------
    override fun onBind(intent: Intent?): IBinder? = null

    // Track whether the incoming call was answered (to detect missed calls)
    private var callWasAnswered   = false
    private var incomingCallerName  = ""
    private var incomingCleanNumber = ""
    private var callStartTimeMs: Long = 0L
    private var activeCallNumber = ""
    private var activeCallDisplayName = ""
    private var activeCallIsIncoming = true
    private var pendingLogSavedForCall = false

    private fun getVibrator(): Vibrator? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(VIBRATOR_SERVICE) as? Vibrator
        }
    }

    private fun startVibration() {
        val vibrator = getVibrator() ?: return
        // Pattern: wait 0ms, vibrate 800ms, pause 600ms, repeat from index 0
        val pattern = longArrayOf(0, 800, 600)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(pattern, 0)
        }
    }

    private fun stopVibration() {
        getVibrator()?.cancel()
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
        startForeground(NOTIFICATION_ID, buildPersistentNotification())
        initCore()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        reRegisterIfNeeded()
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        // App swiped away — keep SIP alive
        reRegisterIfNeeded()
    }

    override fun onDestroy() {
        super.onDestroy()
        // Auto-restart if the OS kills us
        startForegroundService(Intent(this, SipForegroundService::class.java))
    }

    // -----------------------------------------------------------------------
    // Core initialisation
    // -----------------------------------------------------------------------
    private fun initCore() {
        if (core != null) {
            attachCoreListener(core!!)
            return
        }
        try {
            val factory = Factory.instance()
            // TEMP DIAGNOSTIC: surface Linphone's own SIP-level logging into
            // logcat so we can see the actual protocol exchange (e.g.
            // whether a decline/486/603 is really being sent) against a
            // remote PBX we have no server-side access to.
            factory.setLogCollectionPath(applicationContext.cacheDir.absolutePath)
            factory.enableLogcatLogs(true)
            factory.loggingService.setLogLevel(LogLevel.Message)
            val c = factory.createCore(null, null, applicationContext)
            c.start()
            c.isVideoCaptureEnabled = true
            c.isVideoDisplayEnabled = true
            val policy = c.videoActivationPolicy
            policy.automaticallyInitiate = true
            policy.automaticallyAccept = true
            c.videoActivationPolicy = policy
            val nonStaticDevs = c.videoDevicesList.filter { !it.lowercase().contains("static") }
            val frontCam = nonStaticDevs.firstOrNull { it.lowercase().contains("front") || it.contains("1") }
                ?: nonStaticDevs.firstOrNull()
            if (frontCam != null) {
                c.videoDevice = frontCam
            }
            configureCodecs(c)
            attachCoreListener(c)
            core = c
            reRegisterIfNeeded()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun attachCoreListener(c: Core) {
        serviceListener?.let { c.removeListener(it) }
        val listener = object : CoreListenerStub() {
            override fun onCallStateChanged(
                core: Core, call: Call, state: Call.State, message: String
            ) {
                val rawNumber = call.remoteAddress.asStringUriOnly()
                val cleanNum  = rawNumber.replaceFirst(Regex("^sip:"), "").split("@").first()
                val dispName  = call.remoteAddress.displayName?.takeIf { it.isNotBlank() } ?: cleanNum

                when (state) {
                    Call.State.OutgoingInit,
                    Call.State.OutgoingProgress -> {
                        // Track outgoing call start
                        callStartTimeMs        = System.currentTimeMillis()
                        activeCallNumber       = cleanNum
                        activeCallDisplayName  = dispName
                        activeCallIsIncoming   = false
                        callWasAnswered        = false
                        pendingLogSavedForCall = false
                    }
                    Call.State.IncomingReceived -> {
                        callWasAnswered        = false
                        wasDeclinedByUser      = false
                        pendingLogSavedForCall = false
                        callStartTimeMs        = System.currentTimeMillis()
                        activeCallNumber       = cleanNum
                        activeCallDisplayName  = dispName
                        activeCallIsIncoming   = true
                        incomingCleanNumber    = cleanNum
                        incomingCallerName     = dispName
                        if (!isFlutterEngineActive) {
                            showIncomingCallNotification(call)
                            startVibration()
                        }
                    }
                    Call.State.Connected,
                    Call.State.StreamsRunning -> {
                        if (call.dir == Call.Dir.Incoming) callWasAnswered = true
                        stopVibration()
                        cancelIncomingCallNotification()
                    }
                    Call.State.End,
                    Call.State.Error,
                    Call.State.Released -> {
                        stopVibration()
                        cancelIncomingCallNotification()

                        // Missed call notification — only on End
                        if (state == Call.State.End && call.dir == Call.Dir.Incoming && !callWasAnswered &&
                            !wasDeclinedByUser && !isFlutterEngineActive) {
                            showMissedCallNotification(incomingCallerName, incomingCleanNumber)
                        }

                        // Always save call log entry to SharedPreferences exactly once per call
                        if (!pendingLogSavedForCall) {
                            pendingLogSavedForCall = true

                            val isIncoming = (call.dir == Call.Dir.Incoming) || activeCallIsIncoming
                            val direction = when {
                                wasDeclinedByUser -> "rejected"
                                callWasAnswered   -> if (isIncoming) "incoming" else "outgoing"
                                isIncoming        -> "missed"
                                else              -> "outgoing"
                            }
                            val durationSec = if (callWasAnswered && callStartTimeMs > 0) {
                                ((System.currentTimeMillis() - callStartTimeMs) / 1000L).toInt()
                            } else 0

                            val targetNum  = activeCallNumber.ifEmpty { cleanNum }
                            val targetName = activeCallDisplayName.ifEmpty { dispName }

                            if (targetNum.isNotEmpty()) {
                                savePendingCallLog(
                                    number       = targetNum,
                                    displayName  = targetName,
                                    direction    = direction,
                                    timestampMs  = if (callStartTimeMs > 0) callStartTimeMs else System.currentTimeMillis(),
                                    durationSecs = durationSec
                                )
                            }

                            callWasAnswered   = false
                            wasDeclinedByUser = false
                        }
                    }
                    else -> {}
                }
            }
        }
        c.addListener(listener)
        serviceListener = listener
    }

    private fun savePendingCallLog(
        number: String, displayName: String, direction: String,
        timestampMs: Long, durationSecs: Int
    ) {
        try {
            val prefs    = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val key      = "flutter.pending_call_logs"
            val existing = prefs.getString(key, "[]") ?: "[]"
            val arr      = org.json.JSONArray(existing)
            val obj      = org.json.JSONObject()
            obj.put("id",              java.util.UUID.randomUUID().toString())
            obj.put("number",          number)
            obj.put("displayName",     displayName)
            obj.put("direction",       direction)
            obj.put("timestamp",       timestampMs)
            obj.put("durationSeconds", durationSecs)
            arr.put(obj)
            prefs.edit().putString(key, arr.toString()).apply()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }


    // -----------------------------------------------------------------------
    // Re-register
    // -----------------------------------------------------------------------
    private fun reRegisterIfNeeded() {
        val c = core ?: return
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val domain    = prefs.getString("domain",    null) ?: return
        val username  = prefs.getString("username",  null) ?: return
        val password  = prefs.getString("password",  null) ?: return
        val transport = prefs.getString("transport", "UDP") ?: "UDP"

        if (c.defaultAccount?.state != RegistrationState.Ok) {
            registerSip(c, domain, username, password, transport)
        }
    }

    fun registerSip(
        c: Core, domain: String, username: String, password: String, transport: String
    ) {
        try {
            val factory = Factory.instance()
            c.clearAccounts()
            c.clearAllAuthInfo()

            val authInfo = factory.createAuthInfo(username, null, password, null, null, domain, null)
            c.addAuthInfo(authInfo)

            val accountParams = c.createAccountParams()
            accountParams.identityAddress = factory.createAddress("sip:$username@$domain")
            accountParams.serverAddress   = factory.createAddress("sip:$domain")
            accountParams.transport       = when (transport.uppercase()) {
                "TCP" -> TransportType.Tcp
                "TLS" -> TransportType.Tls
                else  -> TransportType.Udp
            }

            val account = c.createAccount(accountParams)
            if (account != null) {
                c.addAccount(account)
                c.defaultAccount = account
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun configureCodecs(c: Core) {
        val allowedAudio = setOf("PCMA", "PCMU", "G729")
        c.audioPayloadTypes.forEach { it.enable(allowedAudio.contains(it.mimeType.uppercase())) }
        c.videoPayloadTypes.forEach { it.enable(true) }
    }

    // -----------------------------------------------------------------------
    // Incoming call notification (native Android — no Flutter engine needed)
    // -----------------------------------------------------------------------
    private fun showIncomingCallNotification(call: Call) {
        val rawNumber = call.remoteAddress.asStringUriOnly()
        val cleanNumber = rawNumber.replaceFirst(Regex("^sip:"), "").split("@").first()
        val displayName = call.remoteAddress.displayName
            ?.takeIf { it.isNotBlank() } ?: cleanNumber

        // Cache for missed call notification
        incomingCleanNumber = cleanNumber
        incomingCallerName  = displayName

        // Full-screen intent — opens MainActivity which shows CallKit UI
        val fullScreenIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("incoming_call", true)
            putExtra("caller_number", cleanNumber)
            putExtra("caller_name", displayName)
        }
        val fullScreenPendingIntent = PendingIntent.getActivity(
            this, 0, fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Accept action — must use PendingIntent.getActivity so Android OS allows
        // launching MainActivity from background when tapping notification buttons
        val acceptIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("action", "answer")
        }
        val acceptPending = PendingIntent.getActivity(
            this, 1, acceptIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Decline action — handles decline in background via CallActionReceiver
        val declineIntent = Intent(ACTION_DECLINE).apply { setClass(this@SipForegroundService, CallActionReceiver::class.java) }
        val declinePending = PendingIntent.getBroadcast(
            this, 2, declineIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val isVideo = call.remoteParams?.isVideoEnabled == true
        val titleText = if (isVideo) "Gelen Görüntülü Arama" else "Gelen Arama"
        val contentText = if (isVideo) "$displayName ($cleanNumber) görüntülü arıyor" else "$displayName ($cleanNumber) arıyor"

        val notification = NotificationCompat.Builder(this, CALL_CHANNEL_ID)
            .setContentTitle(titleText)
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .setOngoing(true)
            .setAutoCancel(false)
            .addAction(android.R.drawable.ic_menu_call, "Kabul Et", acceptPending)
            .addAction(android.R.drawable.ic_delete,    "Reddet",   declinePending)
            .build()

        val nm = getSystemService(NotificationManager::class.java)
        nm.notify(CALL_NOTIFICATION_ID, notification)
    }

    private fun cancelIncomingCallNotification() {
        val nm = getSystemService(NotificationManager::class.java)
        nm.cancel(CALL_NOTIFICATION_ID)
    }

    private fun showMissedCallNotification(displayName: String, cleanNumber: String) {
        // Tapping the notification opens the app
        val openIntent = PendingIntent.getActivity(
            this, 10,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, MISSED_CHANNEL_ID)
            .setContentTitle("Cevapsız Arama")
            .setContentText("$displayName ($cleanNumber) sizi aradı")
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MISSED_CALL)
            .setContentIntent(openIntent)
            .setAutoCancel(true)
            .build()

        val nm = getSystemService(NotificationManager::class.java)
        nm.notify(MISSED_NOTIFICATION_ID, notification)
    }

    // -----------------------------------------------------------------------
    // Notifications & channels
    // -----------------------------------------------------------------------
    private fun createNotificationChannels() {
        val nm = getSystemService(NotificationManager::class.java)

        // Persistent low-priority channel
        nm.createNotificationChannel(NotificationChannel(
            CHANNEL_ID, "SIP Bağlantısı", NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "SIP kayıt durumu bildirimi"
            setShowBadge(false)
        })

        // High-priority incoming-call channel
        nm.createNotificationChannel(NotificationChannel(
            CALL_CHANNEL_ID, "Gelen Aramalar", NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Gelen SIP aramaları için tam ekran bildirim"
            setShowBadge(true)
        })

        // Missed call channel
        nm.createNotificationChannel(NotificationChannel(
            MISSED_CHANNEL_ID, "Cevapsız Aramalar", NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Cevapsız arama bildirimleri"
            setShowBadge(true)
        })
    }

    private fun buildPersistentNotification(): Notification {
        val openIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).apply { flags = Intent.FLAG_ACTIVITY_SINGLE_TOP },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Softphone")
            .setContentText("SIP bağlantısı aktif — gelen aramalar alınıyor")
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
}
