Pod::Spec.new do |s|
  s.name             = 'linphone-sdk'
  s.version          = '5.2.0'
  s.summary          = 'Linphone SDK pre-compiled iOS framework for SIP audio and video calling.'
  s.homepage         = 'https://www.linphone.org/'
  s.license          = { :type => 'GPLv3', :text => 'GNU General Public License v3' }
  s.author           = { 'Belledonne Communications' => 'contact@belledonne-communications.com' }
  s.platform         = :ios, '13.0'
  s.source           = { :http => 'https://download.linphone.org/releases/ios/linphone-sdk-ios-5.2.0.zip' }
  s.vendored_frameworks = 'linphone-sdk-ios-5.2.0/linphone-sdk.xcframework'
  s.pod_target_xcconfig = { 'VALID_ARCHS' => 'arm64 x86_64' }
end
