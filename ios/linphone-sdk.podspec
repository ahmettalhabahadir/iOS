Pod::Spec.new do |s|
  s.name             = 'linphone-sdk'
  s.version          = '5.4.124'
  s.summary          = 'Linphone SDK pre-compiled iOS framework for SIP audio and video calling.'
  s.homepage         = 'https://www.linphone.org/'
  s.license          = { :type => 'GPLv3', :text => 'GNU General Public License v3' }
  s.author           = { 'Belledonne Communications' => 'contact@belledonne-communications.com' }
  s.platform         = :ios, '13.0'
  s.source           = { :http => 'https://download.linphone.org/releases/ios/linphone-sdk-5.4.124.zip' }
  s.vendored_frameworks = '**/XCFrameworks/*.xcframework'
  s.source_files     = '**/share/linphonesw/**/*.swift'
  s.module_name      = 'linphonesw'
  s.swift_version    = '5.0'
  s.static_framework = true
  s.frameworks       = 'AVFoundation', 'AudioToolbox', 'CoreMedia', 'CoreMotion', 'VideoToolbox', 'SystemConfiguration'
  s.libraries        = 'c++', 'sqlite3', 'xml2', 'z'
  s.pod_target_xcconfig  = { 'VALID_ARCHS' => 'arm64 x86_64', 'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES' }
  s.user_target_xcconfig = { 'VALID_ARCHS' => 'arm64 x86_64' }
end
