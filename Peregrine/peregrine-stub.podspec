Pod::Spec.new do |s|
  s.name             = 'peregrine-stub'
  s.version          = '0.2.0'
  s.summary          = 'peregrine-stub'
  s.homepage         = 'https://github.com/zhoujun94511/Peregrine_ios'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = 'Peregrine'
  s.source           = { :git => 'https://github.com/zhoujun94511/Peregrine_ios.git', :tag => s.version.to_s }

  s.ios.deployment_target = '12.0'

  s.vendored_frameworks = []
  s.source_files = "peregrine-stub/*.{h,m,mm}"
  s.dependency 'GCDWebServer', '~> 3.0'
end
