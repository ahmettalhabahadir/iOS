#include "sip_engine.h"

#include <iostream>
#include <sstream>
#include <iomanip>
#include <wincrypt.h>
#pragma comment(lib, "advapi32.lib")

SipEngine::SipEngine() {}

SipEngine::~SipEngine() {
  Shutdown();
}

bool SipEngine::Init() {
  WSADATA wsaData;
  if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) {
    return false;
  }

  socket_ = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
  if (socket_ == INVALID_SOCKET) {
    WSACleanup();
    return false;
  }

  // Bind to dynamic local UDP port
  sockaddr_in local_addr{};
  local_addr.sin_family = AF_INET;
  local_addr.sin_addr.s_addr = INADDR_ANY;
  local_addr.sin_port = 0;

  if (bind(socket_, (sockaddr*)&local_addr, sizeof(local_addr)) == SOCKET_ERROR) {
    closesocket(socket_);
    WSACleanup();
    return false;
  }

  int len = sizeof(local_addr);
  getsockname(socket_, (sockaddr*)&local_addr, &len);
  local_port_ = ntohs(local_addr.sin_port);

  // Get local IP address
  char hostname[256];
  if (gethostname(hostname, sizeof(hostname)) == 0) {
    hostent* host = gethostbyname(hostname);
    if (host && host->h_addr_list[0]) {
      in_addr addr;
      memcpy(&addr, host->h_addr_list[0], sizeof(in_addr));
      local_ip_ = inet_ntoa(addr);
    }
  }
  if (local_ip_.isEmpty() || local_ip_ == "127.0.0.1") {
    local_ip_ = "192.168.4.100"; // Default LAN IP fallback
  }

  is_running_ = true;
  worker_thread_ = std::thread(&SipEngine::NetworkLoop, this);
  return true;
}

void SipEngine::Shutdown() {
  is_running_ = false;
  if (socket_ != INVALID_SOCKET) {
    closesocket(socket_);
    socket_ = INVALID_SOCKET;
  }
  if (worker_thread_.joinable()) {
    worker_thread_.join();
  }
  WSACleanup();
}

bool SipEngine::Register(const std::string& domain, const std::string& username, const std::string& password) {
  domain_ = domain;
  username_ = username;
  password_ = password;

  memset(&server_addr_, 0, sizeof(server_addr_));
  server_addr_.sin_family = AF_INET;
  server_addr_.sin_port = htons(5060);
  inet_pton(AF_INET, domain.c_str(), &server_addr_.sin_addr);

  std::string req = BuildRegisterRequest(cseq_++);
  SendSipPacket(req);

  if (state_callback_) {
    state_callback_(WindowsSipState::Connecting, "Bağlanıyor...");
  }
  return true;
}

void SipEngine::Unregister() {
  if (is_registered_) {
    std::string req = BuildRegisterRequest(cseq_++);
    // Expires: 0
    size_t pos = req.find("Expires: 3600");
    if (pos != std::string::npos) {
      req.replace(pos, 13, "Expires: 0");
    }
    SendSipPacket(req);
    is_registered_ = false;
    if (state_callback_) {
      state_callback_(WindowsSipState::Disconnected, "Bağlantı Kesildi");
    }
  }
}

bool SipEngine::MakeCall(const std::string& target, bool isVideo) {
  current_target_ = target;
  call_id_ = "win_" + std::to_string(rand() % 1000000) + "@" + local_ip_;
  is_in_call_ = true;

  std::string invite = BuildInviteRequest(target, cseq_++);
  SendSipPacket(invite);

  if (state_callback_) {
    state_callback_(WindowsSipState::CallConfirmed, target);
  }
  return true;
}

void SipEngine::Hangup() {
  if (is_in_call_) {
    is_in_call_ = false;
    std::string bye = BuildByeRequest(current_target_, cseq_++);
    SendSipPacket(bye);

    if (state_callback_) {
      state_callback_(WindowsSipState::CallEnded, current_target_);
    }
  }
}

void SipEngine::Answer() {
  if (state_callback_) {
    state_callback_(WindowsSipState::CallConfirmed, current_target_);
  }
}

void SipEngine::ToggleMute(bool enabled) {
  is_muted_ = enabled;
}

void SipEngine::SendSipPacket(const std::string& packet) {
  if (socket_ != INVALID_SOCKET) {
    sendto(socket_, packet.c_str(), (int)packet.length(), 0, (sockaddr*)&server_addr_, sizeof(server_addr_));
  }
}

void SipEngine::NetworkLoop() {
  char buffer[4096];
  sockaddr_in from_addr;
  int from_len = sizeof(from_addr);

  while (is_running_) {
    int bytes = recvfrom(socket_, buffer, sizeof(buffer) - 1, 0, (sockaddr*)&from_addr, &from_len);
    if (bytes > 0) {
      buffer[bytes] = '\0';
      ProcessSipPacket(std::string(buffer, bytes), from_addr);
    }
  }
}

void SipEngine::ProcessSipPacket(const std::string& packet, const sockaddr_in& from) {
  std::istringstream stream(packet);
  std::string line;
  if (!std::getline(stream, line)) return;

  if (line.find("SIP/2.0 200 OK") != std::string::npos) {
    if (packet.find("CSeq: ") != std::string::npos && packet.find("REGISTER") != std::string::npos) {
      is_registered_ = true;
      if (state_callback_) {
        state_callback_(WindowsSipState::Registered, "Kayıtlı");
      }
    }
  } else if (line.find("SIP/2.0 401 Unauthorized") != std::string::npos || line.find("SIP/2.0 407 Proxy Authentication Required") != std::string::npos) {
    // Extract Digest Nonce & Realm
    size_t nonce_pos = packet.find("nonce=\"");
    size_t realm_pos = packet.find("realm=\"");
    if (nonce_pos != std::string::npos && realm_pos != std::string::npos) {
      std::string nonce = packet.substr(nonce_pos + 7, packet.find("\"", nonce_pos + 7) - (nonce_pos + 7));
      std::string realm = packet.substr(realm_pos + 7, packet.find("\"", realm_pos + 7) - (realm_pos + 7));

      std::string uri = "sip:" + domain_;
      std::string auth = CalculateDigestAuth(username_, realm, password_, nonce, uri, "REGISTER");
      std::string auth_header = "Authorization: Digest username=\"" + username_ + "\", realm=\"" + realm + "\", nonce=\"" + nonce + "\", uri=\"" + uri + "\", response=\"" + auth + "\", algorithm=MD5\r\n";

      std::string auth_req = BuildRegisterRequest(cseq_++, auth_header);
      SendSipPacket(auth_req);
    }
  } else if (line.find("INVITE sip:") == 0) {
    // Incoming SIP Call
    size_t from_pos = packet.find("From: ");
    std::string caller = "Unknown";
    if (from_pos != std::string::npos) {
      size_t start = packet.find("sip:", from_pos);
      size_t end = packet.find("@", start);
      if (start != std::string::npos && end != std::string::npos) {
        caller = packet.substr(start + 4, end - (start + 4));
      }
    }
    current_target_ = caller;
    if (incoming_callback_) {
      incoming_callback_(caller, caller, false);
    }
  }
}

std::string SipEngine::BuildRegisterRequest(int cseq, const std::string& authHeader) {
  std::ostringstream ss;
  ss << "REGISTER sip:" << domain_ << " SIP/2.0\r\n";
  ss << "Via: SIP/2.0/UDP " << local_ip_ << ":" << local_port_ << ";branch=z9hG4bK" << rand() << "\r\n";
  ss << "Max-Forwards: 70\r\n";
  ss << "From: <sip:" << username_ << "@" << domain_ << ">;tag=" << rand() << "\r\n";
  ss << "To: <sip:" << username_ << "@" << domain_ << ">\r\n";
  ss << "Call-ID: reg_" << rand() << "@" << local_ip_ << "\r\n";
  ss << "CSeq: " << cseq << " REGISTER\r\n";
  ss << "Contact: <sip:" << username_ << "@" << local_ip_ << ":" << local_port_ << ">\r\n";
  ss << "Expires: 3600\r\n";
  if (!authHeader.empty()) {
    ss << authHeader;
  }
  ss << "Content-Length: 0\r\n\r\n";
  return ss.str();
}

std::string SipEngine::BuildInviteRequest(const std::string& target, int cseq, const std::string& authHeader) {
  std::ostringstream ss;
  std::string sdp = 
    "v=0\r\n"
    "o=" + username_ + " 123456 123456 IN IP4 " + local_ip_ + "\r\n"
    "s=Softphone Call\r\n"
    "c=IN IP4 " + local_ip_ + "\r\n"
    "t=0 0\r\n"
    "m=audio 8000 RTP/AVP 0 8 101\r\n"
    "a=rtpmap:0 PCMU/8000\r\n"
    "a=rtpmap:8 PCMA/8000\r\n"
    "a=rtpmap:101 telephone-event/8000\r\n"
    "a=sendrecv\r\n";

  ss << "INVITE sip:" << target << "@" << domain_ << " SIP/2.0\r\n";
  ss << "Via: SIP/2.0/UDP " << local_ip_ << ":" << local_port_ << ";branch=z9hG4bK" << rand() << "\r\n";
  ss << "Max-Forwards: 70\r\n";
  ss << "From: <sip:" << username_ << "@" << domain_ << ">;tag=" << rand() << "\r\n";
  ss << "To: <sip:" << target << "@" << domain_ << ">\r\n";
  ss << "Call-ID: " << call_id_ << "\r\n";
  ss << "CSeq: " << cseq << " INVITE\r\n";
  ss << "Contact: <sip:" << username_ << "@" << local_ip_ << ":" << local_port_ << ">\r\n";
  ss << "Content-Type: application/sdp\r\n";
  if (!authHeader.empty()) {
    ss << authHeader;
  }
  ss << "Content-Length: " << sdp.length() << "\r\n\r\n";
  ss << sdp;
  return ss.str();
}

std::string SipEngine::BuildByeRequest(const std::string& target, int cseq) {
  std::ostringstream ss;
  ss << "BYE sip:" << target << "@" << domain_ << " SIP/2.0\r\n";
  ss << "Via: SIP/2.0/UDP " << local_ip_ << ":" << local_port_ << ";branch=z9hG4bK" << rand() << "\r\n";
  ss << "Max-Forwards: 70\r\n";
  ss << "From: <sip:" << username_ << "@" << domain_ << ">;tag=" << rand() << "\r\n";
  ss << "To: <sip:" << target << "@" << domain_ << ">\r\n";
  ss << "Call-ID: " << call_id_ << "\r\n";
  ss << "CSeq: " << cseq << " BYE\r\n";
  ss << "Content-Length: 0\r\n\r\n";
  return ss.str();
}

std::string SipEngine::ComputeMd5Hash(const std::string& input) {
  HCRYPTPROV hProv = 0;
  HCRYPTHASH hHash = 0;
  BYTE rgbHash[16];
  DWORD cbHash = 16;
  std::ostringstream hexStream;

  if (CryptAcquireContext(&hProv, NULL, NULL, PROV_RSA_FULL, CRYPT_VERIFYCONTEXT)) {
    if (CryptCreateHash(hProv, CALG_MD5, 0, 0, &hHash)) {
      if (CryptHashData(hHash, (const BYTE*)input.c_str(), (DWORD)input.length(), 0)) {
        if (CryptGetHashParam(hHash, HP_HASHVAL, rgbHash, &cbHash, 0)) {
          for (DWORD i = 0; i < cbHash; i++) {
            hexStream << std::setw(2) << std::setfill('0') << std::hex << (int)rgbHash[i];
          }
        }
      }
      CryptDestroyHash(hHash);
    }
    CryptReleaseContext(hProv, 0);
  }
  return hexStream.str();
}

std::string SipEngine::CalculateDigestAuth(const std::string& username, const std::string& realm,
                                            const std::string& password, const std::string& nonce,
                                            const std::string& uri, const std::string& method) {
  std::string ha1 = ComputeMd5Hash(username + ":" + realm + ":" + password);
  std::string ha2 = ComputeMd5Hash(method + ":" + uri);
  std::string response = ComputeMd5Hash(ha1 + ":" + nonce + ":" + ha2);
  return response;
}
