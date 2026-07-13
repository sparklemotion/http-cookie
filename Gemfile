source 'https://rubygems.org'

# Specify your gem's dependencies in http-cookie.gemspec
gemspec

# rdoc depends on rbs, which ships no java-platform gem before 4.1.0.pre.2, so on
# JRuby bundler tries to compile rbs's native extension and fails.
# See https://github.com/ruby/rdoc/issues/1746
gem 'rbs', '>= 4.1.0.pre.2' if RUBY_PLATFORM == 'java'
