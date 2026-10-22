Pod::Spec.new do |s|
  s.name             = 'seven_motion_ios'
  s.version          = '1.0.0'
  s.summary          = 'Native iPhone support for 7 MOTION.'
  s.description      = 'Private audio-session and Keychain bridge for 7 MOTION.'
  s.homepage         = 'https://github.com/manzilionellm-dotcom/tvking'
  s.license          = { :type => 'Proprietary' }
  s.author           = { '7 MOTION' => 'manzilionel.lm@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.0'
  s.frameworks       = 'AVFoundation', 'Security'
  s.resource_bundles = { 'seven_motion_ios_privacy' => ['Resources/PrivacyInfo.xcprivacy'] }
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
