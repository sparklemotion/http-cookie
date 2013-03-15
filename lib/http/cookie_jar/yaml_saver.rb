require 'http/cookie_jar'
require 'psych' if !defined?(YAML) && RUBY_VERSION == "1.9.2"
require 'yaml'

# YAMLSaver saves and loads cookies in the YAML format.
class HTTP::CookieJar::YAMLSaver < HTTP::CookieJar::AbstractSaver
  def save(io, jar)
    YAML.dump(@session ? jar.to_a : jar.reject(&:session?), io)
  end

  def load(io, jar)
    begin
      data = YAML.load(io)
    rescue ArgumentError
      @logger.warn "unloadable YAML cookie data discarded" if @logger
      return
    end

    unless data.instance_of?(Array)
      @logger.warn "incompatible YAML cookie data discarded" if @logger
      return
    end

    data.each { |cookie|
      jar.add(cookie)
    }
  end

  private

  def default_options
    {}
  end
end
