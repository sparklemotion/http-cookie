# :markup: markdown

# An abstract superclass for all saver classes.
class HTTP::CookieJar::AbstractSaver

  def self.implementation(symbol)
    case symbol
    when :yaml
      HTTP::CookieJar::YAMLSaver
    when :cookiestxt
      HTTP::CookieJar::CookiestxtSaver
    else
      raise IndexError, 'cookie saver unavailable: %s' % symbol.inspect
    end
  end

  # Defines options and their default values.
  def default_options
    # {}
  end
  private :default_options

  # :call-seq:
  #   new(**options)
  #
  # Called by the constructor of each subclass using super().
  def initialize(options = nil)
    options ||= {}
    @logger  = options[:logger]
    @session = options[:session]
    # Initializes each instance variable of the same name as option
    # keyword.
    default_options.each_pair { |key, default|
      instance_variable_set("@#{key}", options.fetch(key, default))
    }
  end

  # Implements HTTP::CookieJar#save().
  #
  # This is an abstract method that each subclass must override.
  def save(io, jar)
    # self
  end

  # Implements HTTP::CookieJar#load().
  #
  # This is an abstract method that each subclass must override.
  def load(io, jar)
    # self
  end
end

require "http/cookie_jar/yaml_saver"
require "http/cookie_jar/cookiestxt_saver"
