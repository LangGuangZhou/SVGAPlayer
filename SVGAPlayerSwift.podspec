Pod::Spec.new do |s|
  s.name             = 'SVGAPlayerSwift'
  s.version          = '1.0.1'
  s.summary          = 'SVGA Player for iOS/macOS (Swift Implementation)'
  s.description      = <<-DESC
    SVGAPlayerSwift is a lightweight animation renderer written in Swift. You use tools to export .svga files from Adobe Animate (formerly Flash) or After Effects, and then use SVGAPlayerSwift to render animation on mobile application.
  DESC

  s.homepage         = 'https://github.com/LangGuangZhou/SVGAPlayer'
  # s.license          = { :type => 'Apache 2.0', :file => 'LICENSE' }
  s.author           = { 'SVGA' => 'https://github.com/LangGuangZhou' }
  s.source           = { :git => 'https://github.com/LangGuangZhou/SVGAPlayer.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '10.11'
  s.requires_arc = true

  s.default_subspecs = 'Core', 'pbobjc'

  s.frameworks = [
    'UIKit',
    'Foundation',
    'AVFoundation',
    'QuartzCore'
  ]

  s.libraries = [
    'z',
    'c++'
  ]

  s.dependency 'SSZipArchive', '~> 2.4'
  s.dependency 'Protobuf', '~> 3.0'

  s.subspec 'Core' do |core|
    core.source_files = '*.{swift,h,m}'
    core.requires_arc = true
  end

  s.subspec 'pbobjc' do |pb|
    pb.source_files = 'pbobjc/*.{h,m}'
    pb.requires_arc = false
    pb.public_header_files = 'pbobjc/*.h'
  end

  s.swift_version = '5.0'
end

