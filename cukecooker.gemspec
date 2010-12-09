spec = Gem::Specification.new do |s|
  s.name = "cukecooker"
  s.version = "0.2"
  s.author = "Ary Borenszweig"
  s.email = "aborenszweig@manas.com.ar"
  s.homepage = "https://github.com/asterite/cukecooker"
  s.platform = Gem::Platform::RUBY
  s.summary = "Write cucumber scenarios with aid"
  s.files = [
    "bin/cukecooker"
  ]
  s.bindir = 'bin'
  s.executables = ['cukecooker']
  s.require_path = '.'
  s.has_rdoc = false
  s.extra_rdoc_files = ["README.rdoc"]
end
