require 'http/cookie_jar'
begin
  require 'psych'
rescue LoadError
end
require 'yaml'

# YAMLSaver saves and loads cookies in the YAML format.
class HTTP::CookieJar::YAMLSaver < HTTP::CookieJar::AbstractSaver
  def save(io, jar)
    YAML.dump(@session ? jar.to_a : jar.reject(&:session?), io)
  end

  def load(io, jar)
    begin
      YAML.load(io)
    rescue ArgumentError
      @logger.warn "incompatible YAML cookie data discarded" if @logger
      return
    end.each { |cookie|
      jar.add(cookie)
    }
  end

  private

  def default_options
    {}
  end
end
