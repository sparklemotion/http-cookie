# :markup: markdown
require 'http/cookie/version'
require 'time'
require 'uri'
require 'domain_name'

module HTTP
  autoload :CookieJar, 'http/cookie_jar'
end

# In Ruby < 1.9.3 URI() does not accept a URI object.
if RUBY_VERSION < "1.9.3"
  begin
    URI(URI(''))
  rescue
    # :nodoc:
    def URI(url)
      url.is_a?(URI) ? url : URI.parse(url)
    end
  end
end

# This class is used to represent an HTTP Cookie.
class HTTP::Cookie
  # Maximum number of bytes per cookie (RFC 6265 6.1 requires 4096 at
  # least)
  MAX_LENGTH = 4096
  # Maximum number of cookies per domain (RFC 6265 6.1 requires 50 at
  # least)
  MAX_COOKIES_PER_DOMAIN = 50
  # Maximum number of cookies total (RFC 6265 6.1 requires 3000 at
  # least)
  MAX_COOKIES_TOTAL = 3000

  # :stopdoc:
  UNIX_EPOCH = Time.at(0)

  PERSISTENT_PROPERTIES = %w[
    name        value
    domain      for_domain  path
    secure      httponly
    expires     created_at  accessed_at
  ]

  if String.respond_to?(:try_convert)
    def check_string_type(object)
      String.try_convert(object)
    end
    private :check_string_type
  else
    def check_string_type(object)
      if object.is_a?(String) ||
          (object.respond_to?(:to_str) && (object = object.to_str).is_a?(String))
        object
      else
        nil
      end
    end
    private :check_string_type
  end
  # :startdoc:

  # The cookie name.  It may not be nil or empty.
  #
  # Trying to set a value with the normal setter method will raise
  # ArgumentError only when it contains any of these characters:
  # control characters (\x00-\x1F and \x7F), space and separators
  # `,;\"=`.
  #
  # Note that RFC 6265 4.1.1 lists more characters disallowed for use
  # in a cookie name, which are these: `<>@:/[]?{}`.  Using these
  # characters will reduce interoperability.
  #
  # :attr_accessor: name

  # The cookie value.
  #
  # Trying to set a value with the normal setter method will raise an
  # ArgumentError only when it contains any of these characters:
  # control characters (\x00-\x1F and \x7F).
  #
  # Note that RFC 6265 4.1.1 lists more characters disallowed for use
  # in a cookie value, which are these: ` ",;\`.  Using these
  # characters will reduce interoperability.
  #
  # :attr_accessor: value

  # The cookie domain.
  #
  # Setting a domain with a leading dot implies that the #for_domain
  # flag should be turned on.  The setter accepts a `DomainName`
  # object as well as a string-like.
  #
  # :attr_accessor: domain

  # The path attribute value.
  #
  # The setter treats an empty path ("") as the root path ("/").
  #
  # :attr_accessor: path

  # The origin of the cookie.
  #
  # Setting this will initialize the #domain and #path attribute
  # values if unknown yet.
  #
  # :attr_accessor: origin

  # The Expires attribute value as a Time object.
  #
  # The setter method accepts a Time object, a string representation
  # of date/time, or `nil`.
  #
  # Note that #max_age and #expires are mutually exclusive.  Setting
  # \#max_age resets #expires to nil, and vice versa.
  #
  # :attr_accessor: expires

  # The Max-Age attribute value as an integer, the number of seconds
  # before expiration.
  #
  # The setter method accepts an integer, or a string-like that
  # represents an integer which will be stringified and then
  # integerized using #to_i.
  #
  # Note that #max_age and #expires are mutually exclusive.  Setting
  # \#max_age resets #expires to nil, and vice versa.
  #
  # :attr_accessor: max_age

  # :call-seq:
  #     new(name, value)
  #     new(name, value, attr_hash)
  #     new(attr_hash)
  #
  # Creates a cookie object.  For each key of `attr_hash`, the setter
  # is called if defined.  Each key can be either a symbol or a
  # string, downcased or not.
  #
  # This methods accepts any attribute name for which a setter method
  # is defined.  Beware, however, any error (typically
  # `ArgumentError`) a setter method raises will be passed through.
  #
  # e.g.
  #
  #     new("uid", "a12345")
  #     new("uid", "a12345", :domain => 'example.org',
  #                          :for_domain => true, :expired => Time.now + 7*86400)
  #     new("name" => "uid", "value" => "a12345", "Domain" => 'www.example.org')
  #
  def initialize(*args)
    @version = 0     # Netscape Cookie

    @origin = @domain = @path =
      @expires = @max_age =
      @comment = nil
    @secure = @httponly = false
    @session = true
    @created_at = @accessed_at = Time.now

    case args.size
    when 2
      self.name, self.value = *args
      @for_domain = false
      return
    when 3
      self.name, self.value, attr_hash = *args
    when 1
      attr_hash = args.first
    else
      raise ArgumentError, "wrong number of arguments (#{args.size} for 1-3)"
    end
    for_domain = false
    origin = nil
    attr_hash.each_pair { |key, val|
      skey = key.to_s.downcase
      if skey.sub!(/\?\z/, '')
        val = val ? true : false
      end
      case skey
      when 'for_domain'
        for_domain = !!val
      when 'origin'
        origin = val
      else
        setter = :"#{skey}="
        send(setter, val) if respond_to?(setter)
      end
    }
    if @name.nil? || @value.nil?
      raise ArgumentError, "at least name and value must be specified"
    end
    @for_domain = for_domain
    if origin
      self.origin = origin
    end
  end

  autoload :Scanner, 'http/cookie/scanner'

  class << self
    # Normalizes a given path.  If it is empty or it is a relative
    # path, the root path '/' is returned.
    #
    # If a URI object is given, returns a new URI object with the path
    # part normalized.
    def normalize_path(path)
      return path + normalize_path(path.path) if URI === path
      # RFC 6265 5.1.4
      path.start_with?('/') ? path : '/'
    end

    # Parses a Set-Cookie header value `set_cookie` into an array of
    # Cookie objects.  Parts (separated by commas) that are malformed
    # or invalid are silently ignored.  For example, a cookie that a
    # given origin is not allowed to issue is not included in the
    # resulted array.
    #
    # Any Max-Age attribute value found is converted to an expires
    # value computing from the current time so that expiration check
    # (#expired?) can be performed.
    #
    # If a block is given, each cookie object is passed to the block.
    #
    # Available option keywords are below:
    #
    # `origin`
    # : The cookie's origin URI/URL
    #
    # `date`
    # : The base date used for interpreting Max-Age attribute values
    #   instead of the current time
    #
    # `logger`
    # : Logger object useful for debugging
    def parse(set_cookie, options = nil, *_, &block)
      _.empty? && !options.is_a?(String) or
        raise ArgumentError, 'HTTP::Cookie equivalent for Mechanize::Cookie.parse(uri, set_cookie[, log]) is HTTP::Cookie.parse(set_cookie, :origin => uri[, :logger => log]).'

      if options
        logger = options[:logger]
        origin = options[:origin] and origin = URI(origin)
        date = options[:date]
      end
      date ||= Time.now

      [].tap { |cookies|
        s = Scanner.new(set_cookie, logger)
        until s.eos?
          name, value, attrs = s.scan_cookie
          break if name.nil? || name.empty?

          cookie = new(name, value)
          attrs.each { |aname, avalue|
            begin
              case aname
              when 'domain'
                cookie.domain = avalue
                cookie.for_domain = true
              when 'path'
                cookie.path = avalue
              when 'expires'
                # RFC 6265 4.1.2.2
                # The Max-Age attribute has precedence over the Expires
                # attribute.
                cookie.expires = avalue unless cookie.max_age
              when 'max-age'
                cookie.max_age = avalue
              when 'comment'
                cookie.comment = avalue
              when 'version'
                cookie.version = avalue
              when 'secure'
                cookie.secure = avalue
              when 'httponly'
                cookie.httponly = avalue
              end
            rescue => e
              logger.warn("Couldn't parse #{aname} '#{avalue}': #{e}") if logger
            end
          }

          # Have `expires` set instead of `max_age`, so that
          # expiration check (`expired?`) can be performed.
          cookie.expires = date + cookie.max_age if cookie.max_age

          if origin
            begin
              cookie.origin = origin
            rescue => e
              logger.warn("Invalid cookie for the origin: #{origin} (#{e})") if logger
              next
            end
          end

          yield cookie if block_given?

          cookies << cookie
        end
      }
    end
  end

  attr_reader :name

  # See #name.
  def name=(name)
    name = check_string_type(name) or
      raise TypeError, "#{name.class} is not a String"
    if name.empty?
      raise ArgumentError, "cookie name cannot be empty"
    elsif name.match(/[\x00-\x20\x7F,;\\"=]/)
      raise ArgumentError, "invalid cookie name"
    end
    # RFC 6265 4.1.1
    # cookie-name may not match:
    # /[\x00-\x20\x7F()<>@,;:\\"\/\[\]?={}]/
    @name = name
  end

  attr_reader :value

  # See #value.
  def value=(value)
    value = check_string_type(value) or
      raise TypeError, "#{value.class} is not a String"
    if value.match(/[\x00-\x1F\x7F]/)
      raise ArgumentError, "invalid cookie value"
    end
    # RFC 6265 4.1.1
    # cookie-name may not match:
    # /[^\x21\x23-\x2B\x2D-\x3A\x3C-\x5B\x5D-\x7E]/
    @value = value
  end

  attr_reader :domain

  # See #domain.
  def domain=(domain)
    if DomainName === domain
      @domain_name = domain
    else
      domain = check_string_type(domain) or
        raise TypeError, "#{domain.class} is not a String"
      if domain.start_with?('.')
        @for_domain = true
        domain = domain[1..-1]
      end
      # Do we really need to support this?
      if domain.match(/\A([^:]+):[0-9]+\z/)
        domain = $1
      end
      @domain_name = DomainName.new(domain)
    end
    @domain = @domain_name.hostname
  end

  # Used to exist in Mechanize::CookieJar.  Use #domain=().
  def set_domain(domain)
    raise NoMethodError, 'HTTP::Cookie equivalent for Mechanize::CookieJar#set_domain() is #domain=().'
  end

  # Returns the domain attribute value as a DomainName object.
  attr_reader :domain_name

  # The domain flag.
  #
  # If this flag is true, this cookie will be sent to any host in the
  # \#domain, including the host domain itself.  If it is false, this
  # cookie will be sent only to the host indicated by the #domain.
  attr_accessor :for_domain
  alias for_domain? for_domain

  attr_reader :path

  # See #path.
  def path=(path)
    path = check_string_type(path) or
      raise TypeError, "#{path.class} is not a String"
    @path = HTTP::Cookie.normalize_path(path)
  end

  attr_reader :origin

  # See #origin.
  def origin=(origin)
    @origin.nil? or
      raise ArgumentError, "origin cannot be changed once it is set"
    origin = URI(origin)
    self.domain ||= origin.host
    self.path   ||= (HTTP::Cookie.normalize_path(origin) + './').path
    acceptable_from_uri?(origin) or
      raise ArgumentError, "unacceptable cookie sent from URI #{origin}"
    @origin = origin
  end

  # The secure flag.
  #
  # A cookie with this flag on should only be sent via a secure
  # protocol like HTTPS.
  attr_accessor :secure
  alias secure? secure

  # The HttpOnly flag.
  #
  # A cookie with this flag on should be hidden from a client script.
  attr_accessor :httponly
  alias httponly? httponly

  # The session flag.
  #
  # A cookie with this flag on should be hidden from a client script.
  attr_reader :session
  alias session? session

  attr_reader :expires

  # See #expires.
  def expires=(t)
    case t
    when nil, Time
    else
      t = Time.parse(t)
    end
    @max_age = nil
    @session = t.nil?
    @expires = t
  end

  alias expires_at expires
  alias expires_at= expires=

  attr_reader :max_age

  # See #max_age.
  def max_age=(sec)
    @expires = nil
    case sec
    when Integer, nil
    else
      str = check_string_type(sec) or
        raise TypeError, "#{sec.class} is not an Integer or String"
      sec = str.to_i
    end
    if @session = sec.nil?
      @max_age = nil
    else
      @max_age = sec
    end
  end

  # Tests if this cookie is expired by now, or by a given time.
  def expired?(time = Time.now)
    return false unless @expires
    time > @expires
  end

  # Expires this cookie by setting the expires attribute value to a
  # past date.
  def expire!
    self.expires = UNIX_EPOCH
    self
  end

  # The version attribute.  The only known version of the cookie
  # format is 0.
  attr_accessor :version

  # The comment attribute.
  attr_accessor :comment

  # The time this cookie was created at.
  attr_accessor :created_at

  # The time this cookie was last accessed at.
  attr_accessor :accessed_at

  # Tests if it is OK to accept this cookie if it is sent from a given
  # `uri`.
  def acceptable_from_uri?(uri)
    uri = URI(uri)
    return false unless URI::HTTP === uri && uri.host
    host = DomainName.new(uri.host)

    # RFC 6265 5.3
    # When the user agent "receives a cookie":
    return @domain.nil? || host.hostname == @domain unless @for_domain

    if host.cookie_domain?(@domain_name)
      true
    elsif host.hostname == @domain
      @for_domain = false
      true
    else
      false
    end
  end

  # Tests if it is OK to send this cookie to a given `uri`.  A runtime
  # error is raised if the cookie's domain is unknown.
  def valid_for_uri?(uri)
    if @domain.nil?
      raise "cannot tell if this cookie is valid because the domain is unknown"
    end
    uri = URI(uri)
    return false if secure? && !(URI::HTTPS === uri)
    acceptable_from_uri?(uri) && HTTP::Cookie.normalize_path(uri.path).start_with?(@path)
  end

  # Returns a string for use in a Cookie header value,
  # i.e. "name=value".
  def cookie_value
    "#{@name}=#{@value}"
  end
  alias to_s cookie_value

  # Returns a string for use in a Set-Cookie header value.  If the
  # cookie does not have an origin set, one must be given from the
  # argument.
  #
  # This method does not check if this cookie will be accepted from
  # the origin.
  def set_cookie_value(origin = nil)
    origin = origin ? URI(origin) : @origin or
      raise "origin must be specified to produce a value for Set-Cookie"

    string = "#{@name}=#{Scanner.quote(@value)}"
    if @for_domain || @domain != DomainName.new(origin.host).hostname
      string << "; Domain=#{@domain}"
    end
    if (HTTP::Cookie.normalize_path(origin) + './').path != @path
      string << "; Path=#{@path}"
    end
    if @max_age
      string << "; Max-Age=#{@max_age}"
    elsif @expires
      string << "; Expires=#{@expires.httpdate}"
    end
    if @comment
      string << "; Comment=#{Scanner.quote(@comment)}"
    end
    if @httponly
      string << "; HttpOnly"
    end
    if @secure
      string << "; Secure"
    end
    string
  end

  def inspect
    '#<%s:' % self.class << PERSISTENT_PROPERTIES.map { |key|
      '%s=%s' % [key, instance_variable_get(:"@#{key}").inspect]
    }.join(', ') << ' origin=%s>' % [@origin ? @origin.to_s : 'nil']

  end

  # Compares the cookie with another.  When there are many cookies with
  # the same name for a URL, the value of the smallest must be used.
  def <=>(other)
    # RFC 6265 5.4
    # Precedence: 1. longer path  2. older creation
    (@name <=> other.name).nonzero? ||
      (other.path.length <=> @path.length).nonzero? ||
      (@created_at <=> other.created_at).nonzero? ||
      @value <=> other.value
  end
  include Comparable

  # YAML serialization helper for Syck.
  def to_yaml_properties
    PERSISTENT_PROPERTIES.map { |name| "@#{name}" }
  end

  # YAML serialization helper for Psych.
  def encode_with(coder)
    PERSISTENT_PROPERTIES.each { |key|
      coder[key.to_s] = instance_variable_get(:"@#{key}")
    }
  end

  # YAML deserialization helper for Syck.
  def init_with(coder)
    yaml_initialize(coder.tag, coder.map)
  end

  # YAML deserialization helper for Psych.
  def yaml_initialize(tag, map)
    map.each { |key, value|
      case key
      when *PERSISTENT_PROPERTIES
        __send__(:"#{key}=", value)
      end
    }
  end
end
