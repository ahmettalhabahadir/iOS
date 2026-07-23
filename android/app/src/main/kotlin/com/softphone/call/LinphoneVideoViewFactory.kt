package com.softphone.call

import android.content.Context
import android.view.TextureView
import android.view.View
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.linphone.core.Core

class LinphoneVideoViewFactory(private val isPreview: Boolean) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return LinphoneVideoView(context, isPreview)
    }
}

class LinphoneVideoView(
    context: Context,
    private val isPreview: Boolean
) : PlatformView {

    private val textureView: TextureView = TextureView(context).apply {
        layoutParams = android.view.ViewGroup.LayoutParams(
            android.view.ViewGroup.LayoutParams.MATCH_PARENT,
            android.view.ViewGroup.LayoutParams.MATCH_PARENT
        )
    }

    init {
        val c: Core? = SipForegroundService.core
        if (c != null) {
            try {
                c.isVideoDisplayEnabled = true
                c.isVideoCaptureEnabled = true
            } catch (e: Exception) {
                e.printStackTrace()
            }
            if (isPreview) {
                c.nativePreviewWindowId = textureView
            } else {
                c.nativeVideoWindowId = textureView
            }

            // Refresh camera hardware selection to trigger internal video capture pipeline
            try {
                val nonStaticDevs = c.videoDevicesList.filter { !it.lowercase().contains("static") }
                val frontCam = nonStaticDevs.firstOrNull { it.lowercase().contains("front") || it.contains("1") }
                    ?: nonStaticDevs.firstOrNull()
                if (frontCam != null) {
                    c.videoDevice = frontCam
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    override fun getView(): View = textureView

    override fun dispose() {
        val c: Core? = SipForegroundService.core
        if (c != null) {
            if (isPreview) {
                if (c.nativePreviewWindowId == textureView) {
                    c.nativePreviewWindowId = null
                }
            } else {
                if (c.nativeVideoWindowId == textureView) {
                    c.nativeVideoWindowId = null
                }
            }
        }
    }
}
