# frozen_string_literal: true

require File.expand_path('helper', File.dirname(__FILE__))

# Regression test for #65 and #66
# no "circular require" warning should appear for any load order of the gem's entry points.
class TestLoadOrder < Test::Unit::TestCase
  LIB = File.expand_path('../lib', File.dirname(__FILE__))

  [
    ['http/cookie'],
    ['http/cookie_jar'],
    ['http-cookie'],
    ['http/cookie', 'http/cookie_jar'],
    ['http/cookie_jar', 'http/cookie']
  ].each_with_index do |requires, i|
    define_method("test_no_circular_require_#{i}") do
      script = requires.map { |r| "require #{r.inspect}" }.join('; ')
      cmd = [RbConfig.ruby, '-w', "-I#{LIB}", '-e', script]
      output = Bundler.with_unbundled_env { IO.popen(cmd, err: %i[child out], &:read) }
      assert_false(output.include?('circular require'), "warning for `#{script}`:\n#{output}")
    end
  end
end
