#ifndef RUNNER_SIP_ENGINE_H_
#define RUNNER_SIP_ENGINE_H_

#include <winsock2.h>
#include <ws2tcpip.h>
#pragma comment(lib, "ws2_32.lib")

#include <string>
#include <functional>
#include <thread>
#include <atomic>
#include <mutex>
#include <memory>
#include <map>

enum class WindowsSipState {
  Disconnected,
  Connecting,
  Registered,
  RegistrationFailed,
  CallConnecting,
  CallConfirmed,
  CallEnded
};

class SipEngine {
 public:
  using StateCallback = std::function<void(WindowsSipState, const std::string& extraInfo)>;
  using IncomingCallCallback = std::function<void(const std::string& callerNumber, const std::string& callerName, bool isVideo)>;

  SipEngine();
  ~SipEngine();

  bool Init();
  void Shutdown();

  bool Register(const std::string& domain, const std::string& username, const std::string& password);
  void Unregister();

  bool MakeCall(const std::string& target, bool isVideo);
  void Hangup();
  void Answer();
  void ToggleMute(bool enabled);

  void SetStateCallback(StateCallback cb) { state_callback_ = cb; }
  void SetIncomingCallCallback(IncomingCallCallback cb) { incoming_callback_ = cb; }

 private:
  void NetworkLoop();
  void ProcessSipPacket(const std::string& packet, const sockaddr_in& from);
  void SendSipPacket(const std::string& packet);

  std::string BuildRegisterRequest(int cseq, const std::string& authHeader = "");
  std::string BuildInviteRequest(const std::string& target, int cseq, const std::string& authHeader = "");
  std::string BuildAckRequest(const std::string& target, int cseq);
  std::string BuildByeRequest(const std::string& target, int cseq);
  std::string Build200OKResponse(const std::string& toTag, const std::string& via, const std::string& callId, int cseq);

  std::string ComputeMd5Hash(const std::string& input);
  std::string CalculateDigestAuth(const std::string& username, const std::string& realm,
                                  const std::string& password, const std::string& nonce,
                                  const std::string& uri, const std::string& method);

  SOCKET socket_ = INVALID_SOCKET;
  sockaddr_in server_addr_;
  std::string local_ip_;
  int local_port_ = 0;

  std::string domain_;
  std::string username_;
  std::string password_;
  std::string call_id_;
  std::string current_target_;
  std::string active_via_;

  int cseq_ = 1;
  bool is_registered_ = false;
  bool is_in_call_ = false;
  bool is_muted_ = false;

  std::atomic<bool> is_running_{false};
  std::thread worker_thread_;
  std::mutex mutex_;

  StateCallback state_callback_;
  IncomingCallCallback incoming_callback_;
};

#endif  // RUNNER_SIP_ENGINE_H_
