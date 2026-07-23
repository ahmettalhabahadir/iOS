class SipAccount {
  const SipAccount({
    required this.wssUrl,
    required this.extension,
    required this.password,
    required this.domain,
    this.displayName = '',
    this.allowSelfSignedCertificate = false,
  });

  final String wssUrl;
  final String extension;
  final String password;
  final String domain;
  final String displayName;

  /// Skips TLS certificate validation on the WSS handshake. Needed for PBXes
  /// that serve a self-signed certificate; leave off otherwise since it
  /// disables protection against man-in-the-middle attacks.
  final bool allowSelfSignedCertificate;

  bool get isComplete =>
      wssUrl.isNotEmpty &&
      extension.isNotEmpty &&
      password.isNotEmpty &&
      domain.isNotEmpty;

  String get sipUri => 'sip:$extension@$domain';

  Map<String, dynamic> toJson() => {
    'wssUrl': wssUrl,
    'extension': extension,
    'password': password,
    'domain': domain,
    'displayName': displayName,
    'allowSelfSignedCertificate': allowSelfSignedCertificate,
  };

  factory SipAccount.fromJson(Map<String, dynamic> json) => SipAccount(
    wssUrl: json['wssUrl'] as String? ?? '',
    extension: json['extension'] as String? ?? '',
    password: json['password'] as String? ?? '',
    domain: json['domain'] as String? ?? '',
    displayName: json['displayName'] as String? ?? '',
    allowSelfSignedCertificate:
        json['allowSelfSignedCertificate'] as bool? ?? false,
  );

  static const empty = SipAccount(
    wssUrl: '',
    extension: '',
    password: '',
    domain: '',
  );

  SipAccount copyWith({
    String? wssUrl,
    String? extension,
    String? password,
    String? domain,
    String? displayName,
    bool? allowSelfSignedCertificate,
  }) {
    return SipAccount(
      wssUrl: wssUrl ?? this.wssUrl,
      extension: extension ?? this.extension,
      password: password ?? this.password,
      domain: domain ?? this.domain,
      displayName: displayName ?? this.displayName,
      allowSelfSignedCertificate:
          allowSelfSignedCertificate ?? this.allowSelfSignedCertificate,
    );
  }
}
