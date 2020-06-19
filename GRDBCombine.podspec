Pod::Spec.new do |s|
  s.name     = 'GRDBCombine'
  s.version  = '1.0.0-beta.3'
  
  s.license  = { :type => 'MIT', :file => 'LICENSE' }
  s.summary  = 'A set of extensions for SQLite, GRDB.swift, and Combine'
  s.homepage = 'https://github.com/groue/GRDBCombine'
  s.author   = { 'Gwendal Roué' => 'gr@pierlis.com' }
  s.source   = { :git => 'https://github.com/groue/GRDBCombine.git', :tag => "v#{s.version}" }
  s.module_name = 'GRDBCombine'
  
  s.swift_versions = ['5.2']
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'
  s.watchos.deployment_target = '6.0'
  s.tvos.deployment_target = '13.0'
  
  s.framework = 'Combine'
  s.default_subspec = 'default'
  
  s.subspec 'default' do |ss|
    ss.source_files = 'Sources/GRDBCombine/*.swift'
    ss.dependency 'GRDB.swift', '~> 5.0-beta'
  end
  
  s.subspec 'SQLCipher' do |ss|
    ss.source_files = 'Sources/GRDBCombine/*.swift'
    ss.dependency 'GRDB.swift/SQLCipher', '~> 5.0-beta'
    ss.xcconfig = {
      'OTHER_SWIFT_FLAGS' => '$(inherited) -DSQLITE_HAS_CODEC -DUSING_SQLCIPHER',
      'OTHER_CFLAGS' => '$(inherited) -DSQLITE_HAS_CODEC -DUSING_SQLCIPHER',
    }
  end
end
