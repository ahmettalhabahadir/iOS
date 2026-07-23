import Flutter
import UIKit
import linphonesw

class LinphoneVideoViewFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger
    private var isPreview: Bool

    init(messenger: FlutterBinaryMessenger, isPreview: Bool) {
        self.messenger = messenger
        self.isPreview = isPreview
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return LinphoneVideoView(
            frame: frame,
            viewId: viewId,
            arguments: args,
            messenger: messenger,
            isPreview: isPreview
        )
    }

    public func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

class LinphoneVideoView: NSObject, FlutterPlatformView {
    private var _view: UIView
    private var isPreview: Bool

    init(
        frame: CGRect,
        viewId: Int64,
        arguments args: Any?,
        messenger: FlutterBinaryMessenger,
        isPreview: Bool
    ) {
        self._view = UIView(frame: frame)
        self._view.backgroundColor = .black
        self._view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.isPreview = isPreview
        super.init()

        bindToLinphoneCore()
    }

    func view() -> UIView {
        return _view
    }

    private func bindToLinphoneCore() {
        guard let lc = AppDelegate.sharedCore else { return }
        
        lc.isVideoDisplayEnabled = true
        lc.isVideoCaptureEnabled = true

        let pointer = Unmanaged.passUnretained(_view).toOpaque()
        if isPreview {
            lc.nativePreviewWindowId = pointer
        } else {
            lc.nativeVideoWindowId = pointer
        }
    }

    deinit {
        guard let lc = AppDelegate.sharedCore else { return }
        let pointer = Unmanaged.passUnretained(_view).toOpaque()
        if isPreview {
            if lc.nativePreviewWindowId == pointer {
                lc.nativePreviewWindowId = nil
            }
        } else {
            if lc.nativeVideoWindowId == pointer {
                lc.nativeVideoWindowId = nil
            }
        }
    }
}
