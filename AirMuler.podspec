Pod::Spec.new do |spec|
  spec.name = "AirMuler"
  spec.version = "0.0.1"
  spec.summary = "Data muling framework"
  spec.homepage = "https://github.com/ankushg/AirMuler"
  spec.license = { type: 'MIT', file: 'LICENSE' }
  spec.authors = { "Ankush Gupta" => 'me@ankushg.com', "Justin Martinez" => "" }

  spec.platform = :ios, "9.3"
  spec.requires_arc = true
  spec.source = { git: "https://github.com/ankushg/AirMuler.git", tag: "v#{spec.version}", submodules: true }
  spec.source_files = "AirMuler/**/*.{h,swift}"

  spec.dependency "Sodium", "~> 0.1"
  spec.dependency "SwiftyJSON", "~> 2.3.2"
end