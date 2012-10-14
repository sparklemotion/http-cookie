# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'http/cookie/version'

Gem::Specification.new do |gem|
  gem.name          = "http-cookie"
  gem.version       = HTTP::Cookie::VERSION
  gem.authors, gem.email = {
    'Akinori MUSHA'   => 'knu@idaemons.org',
    'Aaron Patterson' => 'aaronp@rubyforge.org',
    'Eric Hodel'      => 'drbrain@segment7.net',
    'Mike Dalessio'   => 'mike.dalessio@gmail.com',
  }.instance_eval { [keys, values] }

  gem.description   = %q{A Ruby library to handle HTTP Cookies}
  gem.summary       = %q{A Ruby library to handle HTTP Cookies}
  gem.homepage      = "https://github.com/sparklemotion/http-cookie"

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_runtime_dependency("domain_name", ["~> 0.5"])
end
