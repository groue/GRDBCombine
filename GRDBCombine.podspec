Pod::Spec.new do |s|
  s.name     = 'GRDBCombine'
  s.version  = '0.8.0'
  
  s.license  = { :type => 'MIT', :file => 'LICENSE' }
  s.summary  = 'A set of extensions for SQLite, GRDB.swift, and Combine'
  s.homepage = 'https://github.com/groue/GRDBCombine'
  s.author   = { 'Gwendal Roué' => 'gr@pierlis.com' }
  s.source   = { :git => 'https://github.com/groue/GRDBCombine.git', :tag => "v#{s.version}" }
  s.module_name = 'GRDBCombine'
  
  s.swift_versions = ['5.0']
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'
  s.watchos.deployment_target = '6.0'
  s.tvos.deployment_target = '13.0'
  
  s.framework = 'Combine'
  s.source_files = 'Sources/GRDBCombine/*.swift'
  s.dependency 'GRDB.swift', '~> 4.1'
  
end
