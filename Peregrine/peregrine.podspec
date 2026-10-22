Pod::Spec.new do |s|
  s.name             = 'peregrine'
  s.version          = '0.2.0'
  s.summary          = 'Peregrine'
  s.homepage         = 'https://github.com/zhoujun94511/Peregrine_ios'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = 'Peregrine'
  s.source           = { :git => 'https://github.com/zhoujun94511/Peregrine_ios.git', :tag => s.version.to_s }

  s.ios.deployment_target = '12.0'
  s.osx.deployment_target = '10.13'

  s.subspec 'peregrine-behavior' do |ss|
    ss.source_files = "peregrine-behavior/**/*.{h,m}"
    ss.resource_bundles = {
      'PGBehaviorConfig' => ['peregrine-behavior/config/*']
    }
  end

  s.subspec 'peregrine-runner' do |ss|
    ss.source_files = "peregrine-runner/**/*.{h,m}"
    ss.dependency 'peregrine/peregrine-behavior'
    ss.frameworks = 'XCTest', 'Network'
    ss.pod_target_xcconfig = {
      'ENABLE_TESTING_SEARCH_PATHS' => 'YES',
      'FRAMEWORK_SEARCH_PATHS' => '$(inherited) "$(PLATFORM_DIR)/Developer/Library/Frameworks"'
    }
  end

end
