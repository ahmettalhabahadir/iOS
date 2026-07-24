#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {
  if (sip_engine_) {
    sip_engine_->Shutdown();
  }
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  // Setup Windows Native SIP Engine and MethodChannel
  sip_engine_ = std::make_unique<SipEngine>();
  sip_engine_->Init();

  sip_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "com.softphone.call/sip",
      &flutter::StandardMethodCodec::GetInstance());

  sip_engine_->SetStateCallback([this](WindowsSipState state, const std::string& extraInfo) {
    if (!sip_channel_) return;
    std::string state_str = "DISCONNECTED";
    switch (state) {
      case WindowsSipState::Connecting: state_str = "CONNECTING"; break;
      case WindowsSipState::Registered: state_str = "CONFIRMED"; break;
      case WindowsSipState::RegistrationFailed: state_str = "ENDED"; break;
      case WindowsSipState::CallConfirmed: state_str = "CONFIRMED"; break;
      case WindowsSipState::CallEnded: state_str = "ENDED"; break;
      default: break;
    }
    flutter::EncodableMap args;
    args[flutter::EncodableValue("state")] = flutter::EncodableValue(state_str);
    args[flutter::EncodableValue("target")] = flutter::EncodableValue(extraInfo);
    sip_channel_->InvokeMethod("onCallStateUpdated", std::make_unique<flutter::EncodableValue>(args));
  });

  sip_engine_->SetIncomingCallCallback([this](const std::string& callerNumber, const std::string& callerName, bool isVideo) {
    if (!sip_channel_) return;
    flutter::EncodableMap args;
    args[flutter::EncodableValue("caller")] = flutter::EncodableValue(callerNumber);
    args[flutter::EncodableValue("name")] = flutter::EncodableValue(callerName);
    args[flutter::EncodableValue("isVideo")] = flutter::EncodableValue(isVideo);
    sip_channel_->InvokeMethod("onIncomingCall", std::make_unique<flutter::EncodableValue>(args));
  });

  sip_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        const std::string& method = call.method_name();
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());

        if (method == "register") {
          std::string domain, username, password;
          if (args) {
            auto domain_it = args->find(flutter::EncodableValue("domain"));
            if (domain_it != args->end()) domain = std::get<std::string>(domain_it->second);

            auto user_it = args->find(flutter::EncodableValue("username"));
            if (user_it != args->end()) username = std::get<std::string>(user_it->second);

            auto pass_it = args->find(flutter::EncodableValue("password"));
            if (pass_it != args->end()) password = std::get<std::string>(pass_it->second);
          }
          sip_engine_->Register(domain, username, password);
          result->Success();
        } else if (method == "unregister") {
          sip_engine_->Unregister();
          result->Success();
        } else if (method == "makeCall") {
          std::string target;
          bool isVideo = false;
          if (args) {
            auto target_it = args->find(flutter::EncodableValue("target"));
            if (target_it != args->end()) target = std::get<std::string>(target_it->second);

            auto video_it = args->find(flutter::EncodableValue("video"));
            if (video_it != args->end()) isVideo = std::get<bool>(video_it->second);
          }
          sip_engine_->MakeCall(target, isVideo);
          result->Success();
        } else if (method == "hangup") {
          sip_engine_->Hangup();
          result->Success();
        } else if (method == "answer") {
          sip_engine_->Answer();
          result->Success();
        } else if (method == "mute") {
          bool enabled = false;
          if (args) {
            auto mute_it = args->find(flutter::EncodableValue("enabled"));
            if (mute_it != args->end()) enabled = std::get<bool>(mute_it->second);
          }
          sip_engine_->ToggleMute(enabled);
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (sip_engine_) {
    sip_engine_->Shutdown();
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
