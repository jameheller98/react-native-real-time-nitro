require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "NitroRealTimeNitro"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => min_ios_version_supported, :visionos => 1.0 }
  s.source       = { :git => package["repository"]["url"], :tag => "#{s.version}" }

  s.source_files = [
    # Implementation (Swift)
    "ios/**/*.{swift}",
    # Autolinking/Registration (Objective-C++)
    "ios/**/*.{m,mm}",
    # Implementation (C++ objects)
    "cpp/**/*.{hpp,cpp}",
  ]

  
  s.public_header_files = "ios/**/*.h"
  # libwebsockets - 3rd party library
  s.vendored_frameworks = "3rdparty/ios/libwebsockets.xcframework"

  # Build settings
  s.pod_target_xcconfig = {
    # C++ standard
    # "CLANG_CXX_LANGUAGE_STANDARD" => "c++11",
    # "CLANG_CXX_LIBRARY" => "libc++",
    
    # Header search paths for libwebsockets
    "HEADER_SEARCH_PATHS" => "$(PODS_TARGET_SRCROOT)/3rdparty/ios/libwebsockets.xcframework/ios-arm64/Headers"
    
    # # Other C++ flags
    # "OTHER_CPLUSPLUSFLAGS" => "-fmodules -fcxx-modules",
    
    # # GCC Preprocessor (fixes some header issues)
    # "GCC_PREPROCESSOR_DEFINITIONS" => "$(inherited)"
  }
  
  # s.user_target_xcconfig = {
  #   "CLANG_CXX_LANGUAGE_STANDARD" => "c++20",
  #   "CLANG_CXX_LIBRARY" => "libc++"
  # }

  # Nitrogen autolinking
  load 'nitrogen/generated/ios/NitroRealTimeNitro+autolinking.rb'
  add_nitrogen_files(s)

  s.dependency 'React-jsi'
  s.dependency 'React-callinvoker'
  install_modules_dependencies(s)
end
