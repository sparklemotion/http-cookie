require 'singleton'

class HTTP::Cookie::URIParser
  include Singleton

  REGEXP = {
    ABS_PATH: /\A[^?#]*\z/
  }

  def parse(uri)
    m = /
      \A
      (?<scheme>https?)
      :\/\/
      ((?<userinfo>.*)@)?
      (?<host>[^\/]+)
      (:(?<port>\d+))?
      (?<path>[^?#]*)
      (\?(?<query>[^#]*))?
      (\#(?<fragment>.*))?
    /xi.match(uri.to_s)

    # Not an absolute HTTP/HTTPS URI
    return URI::DEFAULT_PARSER.parse(uri) unless m

    URI.scheme_list[m['scheme'].upcase].new(
      m['scheme'],
      m['userinfo'],
      m['host'],
      m['port'],
      nil, # registry
      m['path'],
      nil, # opaque
      m['query'],
      m['fragment'],
      self
    )
  end

  def convert_to_uri(uri)
    if uri.is_a?(URI::Generic)
      uri
    elsif uri = String.try_convert(uri)
      parse(uri)
    else
      raise ArgumentError, "bad argument (expected URI object or URI string)"
    end
  end
end
