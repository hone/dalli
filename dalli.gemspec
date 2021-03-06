lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)
require 'dalli/version'

Gem::Specification.new do |s|
  s.name = %q{dalli}
  s.version = Dalli::VERSION

  s.authors = ["Mike Perham"]
  s.date = %q{2010-08-28}
  s.description = %q{High performance memcached client for Ruby}
  s.email = %q{mperham@gmail.com}
  s.files = Dir.glob("lib/**/*") + [
     "LICENSE",
     "README.md",
     "History.md",
     "TODO.md",
     "Rakefile",
     "Gemfile",
     "dalli.gemspec",
     "Performance.md",
  ]
  s.homepage = %q{http://github.com/mperham/dalli}
  s.rdoc_options = ["--charset=UTF-8"]
  s.require_paths = ["lib"]
  s.summary = %q{High performance memcached client for Ruby}
  s.test_files = Dir.glob("test/**/*")
  s.add_development_dependency(%q<shoulda>, [">= 0"])
  s.add_development_dependency(%q<mocha>, [">= 0"])
  s.add_development_dependency(%q<activesupport>, [">= 3.0.0"])
  s.add_development_dependency(%q<memcache-client>, [">= 1.8.5"])
end

