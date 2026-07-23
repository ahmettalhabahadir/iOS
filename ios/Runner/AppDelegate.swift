import Flutter
import UIKit
import linphonesw

@main
@objc class AppDelegate: FlutterAppDelegate, CoreDelegate {

    static var sharedCore: Core?
    private var channel: FlutterMethodChannel?
    private var core: Core?
    private var currentAccount: Account?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        guard let controller = window?.rootViewController as? FlutterViewController else {
            return super.application(application, didFinishLaunchingWithOptions: launchOptions)
        }

        channel = FlutterMethodChannel(
            name: "com.softphone.call/sip",
            binaryMessenger: controller.binaryMessenger
        )

        // Register Video Platform Views for iOS
        let remoteFactory = LinphoneVideoViewFactory(messenger: controller.binaryMessenger, isPreview: false)
        registrar(forPlugin: "LinphoneVideoViewRemote")?.register(remoteFactory, withId: "com.softphone.call/remote_video_view")

        let localFactory = LinphoneVideoViewFactory(messenger: controller.binaryMessenger, isPreview: true)
        registrar(forPlugin: "LinphoneVideoViewLocal")?.register(localFactory, withId: "com.softphone.call/local_preview_view")

        channel?.setMethodCallHandler { [weak self] (call, result) in
            self?.handleMethodCall(call, result: result)
        }

        DispatchQueue.main.async { [weak self] in
            self?.initLinphoneCore()
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func initLinphoneCore() {
        guard core == nil else { return }
        do {
            let factory = Factory.Instance
            let c = try factory.createCore(configPath: nil, factoryConfigPath: nil, systemContext: nil)
            c.addDelegate(delegate: self)

            c.videoCaptureEnabled = true
            c.videoDisplayEnabled = true

            if let policy = c.videoActivationPolicy {
                policy.automaticallyInitiate = true
                policy.automaticallyAccept = true
                c.videoActivationPolicy = policy
            }

            try c.start()
            self.core = c
            AppDelegate.sharedCore = c
            print("[iOS Linphone] Core initialized successfully")
        } catch {
            print("[iOS Linphone] Core initialization deferred: \(error)")
        }
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let c = core else {
            result(FlutterError(code: "UNAVAILABLE", message: "Core not initialized", details: nil))
            return
        }

        switch call.method {
        case "register":
            guard let args = call.arguments as? [String: Any],
                  let domain = args["domain"] as? String,
                  let username = args["username"] as? String,
                  let password = args["password"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing sip parameters", details: nil))
                return
            }
            let transport = (args["transport"] as? String) ?? "UDP"
            registerSip(domain: domain, username: username, password: password, transport: transport)
            result(nil)

        case "unregister":
            if let acc = currentAccount {
                c.removeAccount(account: acc)
                currentAccount = nil
            }
            result(nil)

        case "makeCall":
            guard let args = call.arguments as? [String: Any],
                  let target = args["target"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing target", details: nil))
                return
            }
            let isVideo = (args["video"] as? Bool) ?? false
            makeCall(target: target, video: isVideo)
            result(nil)

        case "answer":
            if let currentCall = c.currentCall ?? c.calls.first(where: { $0.state == .IncomingReceived }) {
                let isVideo = currentCall.remoteParams?.videoEnabled ?? false
                if let params = try? c.createCallParams(call: currentCall) {
                    params.videoEnabled = isVideo
                    try? currentCall.acceptWithParams(params: params)
                } else {
                    try? currentCall.accept()
                }
            }
            result(nil)

        case "hangup":
            if let currentCall = c.currentCall ?? c.calls.first {
                try? currentCall.terminate()
            }
            result(nil)

        case "mute":
            if let args = call.arguments as? [String: Any],
               let enabled = args["enabled"] as? Bool {
                c.micEnabled = !enabled
            }
            result(nil)

        case "toggleHold":
            if let currentCall = c.currentCall {
                if currentCall.state == .StreamsRunning {
                    try? currentCall.pause()
                } else if currentCall.state == .Paused {
                    try? currentCall.resume()
                }
            }
            result(nil)

        case "setSpeaker":
            // Managed natively via AVAudioSession on iOS
            result(nil)

        case "toggleCamera":
            if let args = call.arguments as? [String: Any],
               let enabled = args["enabled"] as? Bool {
                c.videoCaptureEnabled = enabled
            }
            result(nil)

        case "switchCamera":
            let currentDev = c.videoDevice
            let devs = c.videoDevicesList
            if let nextDev = devs.first(where: { $0 != currentDev }) {
                try? c.setVideodevice(newValue: nextDev)
            }
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func registerSip(domain: String, username: String, password: String, transport: String) {
        guard let c = core else { return }
        do {
            let authInfo = try Factory.Instance.createAuthInfo(
                username: username,
                userid: username,
                passwd: password,
                ha1: "",
                realm: "",
                domain: domain
            )
            c.addAuthInfo(info: authInfo)

            let identityUri = "sip:\(username)@\(domain)"
            let identity = try Factory.Instance.createAddress(addr: identityUri)
            let serverUri = "sip:\(domain);transport=\(transport.lowercased())"
            let serverAddr = try Factory.Instance.createAddress(addr: serverUri)

            let params = try c.createAccountParams()
            try params.setIdentityaddress(newValue: identity)
            try params.setServeraddress(newValue: serverAddr)
            params.registerEnabled = true

            let account = try c.createAccount(params: params)
            try c.addAccount(account: account)
            c.defaultAccount = account
            self.currentAccount = account
        } catch {
            print("[iOS Linphone] Registration setup failed: \(error)")
        }
    }

    private func makeCall(target: String, video: Bool) {
        guard let c = core else { return }
        let targetUri = target.contains("@") ? target : "sip:\(target)@\(c.defaultAccount?.params?.domain ?? "")"
        do {
            let addr = try Factory.Instance.createAddress(addr: targetUri)
            if let params = try? c.createCallParams(call: nil) {
                params.videoEnabled = video
                _ = c.inviteAddressWithParams(addr: addr, params: params)
            }
        } catch {
            print("[iOS Linphone] Make call failed: \(error)")
        }
    }

    // MARK: - CoreDelegate Call & Registration Handlers

    func onAccountRegistrationStateChanged(core: Core, account: Account, state: RegistrationState, message: String) {
        var statusStr = "disconnected"
        switch state {
        case .Progress:
            statusStr = "connecting"
        case .Ok:
            statusStr = "registered"
        case .Failed:
            statusStr = "registrationFailed"
        default:
            statusStr = "disconnected"
        }

        DispatchQueue.main.async { [weak self] in
            self?.channel?.invokeMethod("onRegistrationStateChanged", arguments: [
                "state": statusStr,
                "message": message
            ])
        }
    }

    func onCallStateChanged(core: Core, call: Call, state: Call.State, message: String) {
        let isVideo = call.currentParams?.videoEnabled ?? false || call.remoteParams?.videoEnabled ?? false
        let remoteIdentity = call.remoteAddress?.asStringUriOnly() ?? ""
        let mappedState = mapCallState(state)

        DispatchQueue.main.async { [weak self] in
            self?.channel?.invokeMethod("onCallStateChanged", arguments: [
                "state": mappedState,
                "message": message,
                "remoteIdentity": remoteIdentity,
                "isVideo": isVideo
            ])
        }
    }

    private func mapCallState(_ state: Call.State) -> String {
        switch state {
        case .IncomingReceived, .IncomingEarlyMedia:
            return "incoming"
        case .OutgoingInit, .OutgoingProgress, .OutgoingRinging, .OutgoingEarlyMedia:
            return "outgoing"
        case .Connected, .StreamsRunning:
            return "connected"
        case .Paused, .Pausing:
            return "onHold"
        case .End, .Released, .Error:
            return "disconnected"
        default:
            return "idle"
        }
    }
}
