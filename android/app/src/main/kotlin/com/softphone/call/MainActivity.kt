package com.softphone.call

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.linphone.core.*

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.softphone.call/sip"
    private var channel: MethodChannel? = null

    // Core lives in SipForegroundService (survives activity restarts)
    private val core: Core? get() = SipForegroundService.core

    private fun mapCallState(state: Call.State): String = when (state) {
        Call.State.OutgoingInit -> "CONNECTING"
        Call.State.OutgoingProgress -> "PROGRESS"
        Call.State.IncomingReceived -> "INCOMING"
        Call.State.Connected, Call.State.StreamsRunning -> "CONFIRMED"
        Call.State.Paused, Call.State.PausedByRemote -> "HOLD"
        Call.State.End, Call.State.Released, Call.State.Error -> "ENDED"
        else -> "NONE"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "com.softphone.call/remote_video_view",
            LinphoneVideoViewFactory(isPreview = false)
        )
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "com.softphone.call/local_preview_view",
            LinphoneVideoViewFactory(isPreview = true)
        )

        initLinphone()
        
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "register" -> {
                    val domain = call.argument<String>("domain") ?: ""
                    val username = call.argument<String>("username") ?: ""
                    val password = call.argument<String>("password") ?: ""
                    val transport = call.argument<String>("transport") ?: "UDP"
                    register(domain, username, password, transport)
                    result.success(true)
                }
                "unregister" -> {
                    unregister()
                    result.success(true)
                }
                "makeCall" -> {
                    val target = call.argument<String>("target") ?: ""
                    val video = call.argument<Boolean>("video") ?: false
                    makeCall(target, video)
                    result.success(true)
                }
                "hangup" -> {
                    hangup()
                    result.success(true)
                }
                "answer" -> {
                    answer()
                    result.success(true)
                }
                "mute" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    mute(enabled)
                    result.success(true)
                }
                "speaker" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    speaker(enabled)
                    result.success(true)
                }
                "toggleHold" -> {
                    toggleHold()
                    result.success(true)
                }
                "toggleCamera" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    toggleCamera(enabled)
                    result.success(true)
                }
                "switchCamera" -> {
                    switchCamera()
                    result.success(true)
                }
                "transfer" -> {
                    val target = call.argument<String>("target") ?: ""
                    transfer(target)
                    result.success(true)
                }
                "startAttendedTransfer" -> {
                    val target = call.argument<String>("target") ?: ""
                    startAttendedTransfer(target)
                    result.success(true)
                }
                "completeAttendedTransfer" -> {
                    completeAttendedTransfer()
                    result.success(true)
                }
                "cancelAttendedTransfer" -> {
                    cancelAttendedTransfer()
                    result.success(true)
                }
                "addToConference" -> {
                    val target = call.argument<String>("target") ?: ""
                    addToConference(target)
                    result.success(true)
                }
                "mergeToConference" -> {
                    mergeToConference()
                    result.success(true)
                }
                "removeFromConference" -> {
                    val remoteIdentity = call.argument<String>("remoteIdentity") ?: ""
                    removeFromConference(remoteIdentity)
                    result.success(true)
                }
                "transferConference" -> {
                    val target = call.argument<String>("target") ?: ""
                    transferConference(target)
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun initLinphone() {
        // Start the foreground service (which creates and owns the Core)
        SipForegroundService.start(applicationContext)
        // The service initializes the core asynchronously — attach our listener
        // once the core is available (retry up to 20 times over 2 seconds)
        attachListenerWithRetry(retries = 20)
    }

    private fun attachListenerWithRetry(retries: Int) {
        val c = SipForegroundService.core
        if (c != null) {
            try {
                // Remove the previous MainActivity/engine instance's listener
                // first - otherwise every recreation stacks another one on this
                // same long-lived Core and Dart receives every call event once
                // per stacked listener (see the doc comment on activityListener).
                SipForegroundService.activityListener?.let { c.removeListener(it) }
                val coreListener = object : CoreListenerStub() {
                    override fun onAccountRegistrationStateChanged(core: Core, account: Account, state: RegistrationState, message: String) {
                        val statusStr = when(state) {
                            RegistrationState.Ok -> "REGISTERED"
                            RegistrationState.Failed -> "REGISTRATION_FAILED"
                            RegistrationState.Cleared -> "UNREGISTERED"
                            else -> "CONNECTING"
                        }
                        runOnUiThread {
                            channel?.invokeMethod("onRegistrationStateChanged", mapOf(
                                "state" to statusStr,
                                "message" to message
                            ))
                        }
                    }

                    override fun onCallStateChanged(core: Core, call: Call, state: Call.State, message: String) {
                        val isVideo = call.currentParams?.isVideoEnabled == true || call.remoteParams?.isVideoEnabled == true
                        if (state == Call.State.StreamsRunning && isVideo) {
                            core.isVideoCaptureEnabled = true
                            core.isVideoDisplayEnabled = true
                        }
                        val remoteIdentity = call.remoteAddress.asStringUriOnly()
                        runOnUiThread {
                            channel?.invokeMethod("onCallStateChanged", mapOf(
                                "state" to mapCallState(state),
                                "message" to message,
                                "remoteIdentity" to remoteIdentity,
                                "isVideo" to isVideo
                            ))
                        }
                    }
                }
                c.addListener(coreListener)
                SipForegroundService.activityListener = coreListener

                // The native notification's Accept button only launches us
                // with this extra - it deliberately doesn't accept() the
                // call itself (see CallActionReceiver), since doing so
                // before Android recognizes this process as foreground left
                // calls connected with no audio until the app was manually
                // reopened. Accept it now, before syncing call state below,
                // so Dart sees CONFIRMED directly instead of flashing an
                // INCOMING call UI for a call that's already being answered.
                if (intent?.getStringExtra("action") == "answer") {
                    c.calls.find { it.state == Call.State.IncomingReceived }?.accept()
                }

                // Catch Dart up on any call already in progress - e.g. the
                // one just accepted above, whose Connected/StreamsRunning
                // event this freshly-attached listener didn't exist yet to
                // observe. Without this, audio works fine (the Core doesn't
                // need Dart for that) but Dart never learns the call
                // exists, so the active-call screen never opens.
                //
                // Delayed: this runs inside configureFlutterEngine(), which
                // fires on a cold start before Dart's widget tree (and the
                // Navigator CallCoordinator needs to push the active-call
                // route) has necessarily finished building yet. Sending the
                // sync immediately meant CallCoordinator's
                // navigatorKey.currentState was still null, so
                // _openActiveCallScreen() silently no-opped and the call
                // connected with no screen ever appearing.
                val calls = c.calls.toList()
                if (calls.isNotEmpty()) {
                    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                        calls.forEach { call ->
                            val remoteIdentity = call.remoteAddress.asStringUriOnly()
                            // Dart infers call direction from this message text
                            // containing "incoming" (see SipService._handleNativeMethodCall)
                            // - keep that convention so a synced call's history
                            // entry doesn't end up mislabeled as outgoing.
                            val syncMessage = if (call.dir == Call.Dir.Incoming) "sync incoming" else "sync outgoing"
                            channel?.invokeMethod("onCallStateChanged", mapOf(
                                "state" to mapCallState(call.state),
                                "message" to syncMessage,
                                "remoteIdentity" to remoteIdentity
                            ))
                        }
                    }, 1000)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        } else if (retries > 0) {
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                attachListenerWithRetry(retries - 1)
            }, 100)
        }
    }

    private fun register(domain: String, username: String, password: String, transport: String) {
        try {
            val c = SipForegroundService.core ?: return
            // Save credentials so service can re-register after being killed
            SipForegroundService.saveCredentials(applicationContext, domain, username, password, transport)
            // Use the service's register logic directly on the shared core
            val factory = Factory.instance()
            c.clearAccounts()
            c.clearAllAuthInfo()
            val authInfo = factory.createAuthInfo(username, null, password, null, null, domain, null)
            c.addAuthInfo(authInfo)
            val identity = factory.createAddress("sip:$username@$domain")
            val serverAddress = factory.createAddress("sip:$domain")
            val accountParams = c.createAccountParams()
            accountParams.identityAddress = identity
            accountParams.serverAddress = serverAddress
            val transportType = when (transport.uppercase()) {
                "TCP" -> TransportType.Tcp
                "TLS" -> TransportType.Tls
                else -> TransportType.Udp
            }
            accountParams.transport = transportType
            val account = c.createAccount(accountParams)
            if (account != null) {
                c.addAccount(account)
                c.defaultAccount = account
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun unregister() {
        try {
            val c = core ?: return
            SipForegroundService.clearCredentials(applicationContext)
            c.clearAccounts()
            c.clearAllAuthInfo()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun makeCall(target: String, video: Boolean) {
        try {
            val factory = Factory.instance()
            val c = core ?: return
            val defaultAcc = c.defaultAccount
            val domain = defaultAcc?.params?.serverAddress?.domain ?: ""
            val destination = "sip:$target@$domain"
            val address = factory.createAddress(destination)
            if (address != null) {
                val callParams = c.createCallParams(null) ?: return
                callParams.isVideoEnabled = video
                c.inviteAddressWithParams(address, callParams)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun hangup() {
        try {
            val c = core ?: return
            val incoming = c.calls.find {
                it.dir == Call.Dir.Incoming &&
                it.state != Call.State.Connected &&
                it.state != Call.State.StreamsRunning
            }
            if (incoming != null) {
                SipForegroundService.wasDeclinedByUser = true
                try {
                    incoming.accept()
                } catch (e: Exception) {
                    e.printStackTrace()
                }
                incoming.terminate()
            } else {
                val currentCall = c.currentCall
                if (currentCall != null) {
                    currentCall.terminate()
                } else {
                    c.terminateAllCalls()
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun answer() {
        try {
            val c = core ?: return
            val ringingCall = c.calls.find {
                it.state == Call.State.IncomingReceived || it.state == Call.State.IncomingEarlyMedia
            } ?: c.currentCall
            if (ringingCall != null) {
                val isVideo = ringingCall.remoteParams?.isVideoEnabled == true
                c.isVideoCaptureEnabled = isVideo
                c.isVideoDisplayEnabled = isVideo
                if (isVideo && c.videoDevice.isNullOrEmpty()) {
                    val frontCam = c.videoDevicesList.firstOrNull { it.lowercase().contains("front") }
                        ?: c.videoDevicesList.firstOrNull()
                    if (frontCam != null) {
                        c.videoDevice = frontCam
                    }
                }
                val params = c.createCallParams(ringingCall)
                if (params != null) {
                    if (isVideo) {
                        params.isVideoEnabled = true
                    }
                    ringingCall.acceptWithParams(params)
                } else {
                    ringingCall.accept()
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun mute(enabled: Boolean) {
        try {
            val c = core ?: return
            c.isMicEnabled = !enabled
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun speaker(enabled: Boolean) {
        try {
            val c = core ?: return
            val speakerDevice = c.audioDevices.find { it.type == AudioDevice.Type.Speaker }
            val earpieceDevice = c.audioDevices.find { it.type == AudioDevice.Type.Earpiece }
            val selectedDevice = if (enabled) speakerDevice else earpieceDevice
            if (selectedDevice != null) {
                c.currentCall?.outputAudioDevice = selectedDevice
                c.outputAudioDevice = selectedDevice
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun toggleHold() {
        try {
            val c = core ?: return
            val currentCall = c.currentCall
            if (currentCall != null) {
                if (currentCall.state == Call.State.Paused) {
                    currentCall.resume()
                } else {
                    currentCall.pause()
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun toggleCamera(enabled: Boolean) {
        try {
            val c = core ?: return
            val current = c.currentCall ?: c.calls.firstOrNull()
            if (current != null) {
                val params = c.createCallParams(current)
                if (params != null) {
                    params.isVideoEnabled = enabled
                    current.update(params)
                }
            }
            c.isVideoCaptureEnabled = enabled
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun switchCamera() {
        try {
            val c = core ?: return
            val currentDev = c.videoDevice
            val devices = c.videoDevicesList
            if (devices.size > 1) {
                val next = devices.firstOrNull { it != currentDev } ?: devices.first()
                c.videoDevice = next
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun transfer(target: String) {
        try {
            val c = core ?: return
            val currentCall = c.currentCall ?: return
            val factory = Factory.instance()
            val defaultAcc = c.defaultAccount
            val domain = defaultAcc?.params?.serverAddress?.domain ?: ""
            val destination = "sip:$target@$domain"
            val address = factory.createAddress(destination)
            if (address != null) {
                currentCall.transferTo(address)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun startAttendedTransfer(target: String) {
        try {
            val c = core ?: return
            val currentCall = c.currentCall
            if (currentCall != null && currentCall.state != Call.State.Paused) {
                currentCall.pause()
            }
            val factory = Factory.instance()
            val defaultAcc = c.defaultAccount
            val domain = defaultAcc?.params?.serverAddress?.domain ?: ""
            val destination = "sip:$target@$domain"
            val address = factory.createAddress(destination)
            if (address != null) {
                val callParams = c.createCallParams(null) ?: return
                callParams.isVideoEnabled = false
                c.inviteAddressWithParams(address, callParams)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun completeAttendedTransfer() {
        try {
            val c = core ?: return
            val pausedCall = c.calls.find { it.state == Call.State.Paused }
            val activeCall = c.calls.find { it.state == Call.State.StreamsRunning || it.state == Call.State.Connected }
            if (pausedCall != null && activeCall != null) {
                pausedCall.transferToAnother(activeCall)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun cancelAttendedTransfer() {
        try {
            val c = core ?: return
            val pausedCall = c.calls.find { it.state == Call.State.Paused }
            val activeCall = c.calls.find { it.state == Call.State.StreamsRunning || it.state == Call.State.Connected || it.state == Call.State.OutgoingProgress }
            activeCall?.terminate()
            pausedCall?.resume()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun addToConference(target: String) {
        try {
            val c = core ?: return
            val currentCall = c.currentCall
            if (currentCall != null && currentCall.state != Call.State.Paused) {
                currentCall.pause()
            }
            val factory = Factory.instance()
            val defaultAcc = c.defaultAccount
            val domain = defaultAcc?.params?.serverAddress?.domain ?: ""
            val destination = "sip:$target@$domain"
            val address = factory.createAddress(destination)
            if (address != null) {
                val callParams = c.createCallParams(null) ?: return
                callParams.isVideoEnabled = false
                c.inviteAddressWithParams(address, callParams)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun mergeToConference() {
        try {
            val c = core ?: return
            c.addAllToConference()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun removeFromConference(remoteIdentity: String) {
        try {
            val c = core ?: return
            // Strip any parameters from the remoteIdentity
            val cleanId = remoteIdentity.split(';').first()
            val targetCall = c.calls.find { it.remoteAddress.asStringUriOnly().split(';').first() == cleanId }
            if (targetCall != null) {
                targetCall.terminate()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun transferConference(target: String) {
        try {
            val c = core ?: return
            val factory = Factory.instance()
            val defaultAcc = c.defaultAccount
            val domain = defaultAcc?.params?.serverAddress?.domain ?: ""
            val destination = "sip:$target@$domain"
            val address = factory.createAddress(destination) ?: return
            
            c.calls.forEach { call ->
                call.transferTo(address)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // Covers tapping the notification's Accept button while the
        // Activity was merely backgrounded rather than fully killed, in
        // which case configureFlutterEngine (and its own "answer" check)
        // never runs again for this launch.
        if (intent.getStringExtra("action") == "answer") {
            core?.calls?.find { it.state == Call.State.IncomingReceived }?.accept()
        }
    }

    override fun onStart() {
        super.onStart()
        // Signal service that Flutter engine is alive — it won't save pending call logs
        SipForegroundService.isFlutterEngineActive = true
    }

    override fun onDestroy() {
        // Flutter engine is going away — service will now save call logs to SharedPreferences
        SipForegroundService.isFlutterEngineActive = false
        super.onDestroy()
    }
}
