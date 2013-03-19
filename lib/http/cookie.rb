require 'http/cookie/version'
require 'time'
require 'uri'
require 'domain_name'

module HTTP
  autoload :CookieJar, 'http/cookie_jar'
end

# In Ruby < 1.9.3 URI() does not accept an URI object.
if RUBY_VERSION < "1.9.3"
  begin
    URI(URI(''))
  rescue
    def URI(url)
      url.is_a?(URI) ? url : URI.parse(url)
    end
  end
end

# This class is used to represent an HTTP Cookie.
class HTTP::Cookie
  # Maximum number of bytes per cookie (RFC 6265 6.1 requires 4096 at least)
  MAX_LENGTH = 4096
  # Maximum number of cookies per domain (RFC 6265 6.1 requires 50 at least)
  MAX_COOKIES_PER_DOMAIN = 50
  # Maximum number of cookies total (RFC 6265 6.1 requires 3000 at least)
  MAX_COOKIES_TOTAL = 3000

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

  attr_reader :name, :domain, :path, :origin
  attr_accessor :secure, :httponly, :value, :version
  attr_reader :domain_name, :expires, :max_age
  attr_accessor :comment

  attr_reader :session

  attr_accessor :created_at
  attr_accessor :accessed_at

  # :call-seq:
  #     new(name, value)
  #     new(name, value, attr_hash)
  #     new(attr_hash)
  #
  # Creates a cookie object.  For each key of +attr_hash+, the setter
  # is called if defined.  Each key can be either a symbol or a
  # string, downcased or not.
  #
  # This methods accepts any attribute name for which a setter method
  # is defined.  Beware, however, any error (typically ArgumentError)
  # a setter method raises will be passed through.
  #
  # e.g.
  #     new("uid", "a12345")
  #     new("uid", "a12345", :domain => 'example.org',
  #                          :for_domain => true, :expired => Time.now + 7*86400)
  #     new("name" => "uid", "value" => "a12345", "Domain" => 'www.example.org')
  #
  def initialize(*args)
    @version = 0     # Netscape Cookie

    @origin = @domain = @path =
      @secure = @httponly =
      @expires = @max_age =
      @comment = nil
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

  # If this flag is true, this cookie will be sent to any host in the
  # +domain+.  If it is false, this cookie will be sent only to the
  # host indicated by the +domain+.
  attr_accessor :for_domain
  alias for_domain? for_domain

  class << self
    # Normalizes a given path.  If it is empty, the root path '/' is
    # returned.  If a URI object is given, returns a new URI object
    # with the path part normalized.
    def normalize_path(uri)
      # Currently does not replace // to /
      case uri
      when URI
        uri.path.empty? ? uri + '/' : uri
      else
        uri.empty? ? '/' : uri
      end
    end

    # Parses a Set-Cookie header value +set_cookie+ into an array of
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
    # * +origin+
    #   The cookie's origin URI/URL
    # * +date+
    #   The base date used for interpreting Max-Age attribute values
    #   instead of the current time
    # * +logger+
    #   Logger object useful for debugging
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
        # The expires attribute may include a comma in the value.
        set_cookie.split(/,(?=[^;,]*=|\s*\z)/).each { |c|
          if c.bytesize > MAX_LENGTH
            logger.warn("Cookie definition too long: #{c}") if logger
            next
          end

          first_elem, *cookie_elem = c.split(/;+/)
          first_elem.strip!
          key, value = first_elem.split(/\=/, 2)
          # RFC 6265 2.2
          # A cookie-value may be DQUOTE'd.
          case value
          when /\A"(.*)"\z/
            value = $1.gsub(/\\(.)/, "\\1")
          end

          begin
            cookie = new(key, value.dup)
          rescue
            logger.warn("Couldn't parse key/value: #{first_elem}") if logger
            next
          end

          cookie_elem.each do |pair|
            pair.strip!
            key, value = pair.split(/=/, 2) #/)
            next unless key
            case value # may be nil
            when /\A"(.*)"\z/
              value = $1.gsub(/\\(.)/, "\\1")
            end

            case key.downcase
            when 'domain'
              next unless value && !value.empty?
              begin
                cookie.domain = value
                cookie.for_domain = true
              rescue
                logger.warn("Couldn't parse domain: #{value}") if logger
              end
            when 'path'
              next unless value && !value.empty?
              cookie.path = value
            when 'expires'
              # RFC 6265 4.1.2.2
              # The Max-Age attribute has precedence over the Expires
              # attribute.
              next unless value && !value.empty? && cookie.max_age.nil?
              begin
                cookie.expires = Time.parse(value)
              rescue
                logger.warn("Couldn't parse expires: #{value}") if logger
              end
            when 'max-age'
              next unless value && !value.empty?
              begin
                cookie.max_age = Integer(value)
              rescue
                logger.warn("Couldn't parse max age '#{value}'") if logger
              end
            when 'comment'
              next unless value
              cookie.comment = value
            when 'version'
              next unless value
              begin
                cookie.version = Integer(value)
              rescue
                logger.warn("Couldn't parse version '#{value}'") if logger
                cookie.version = nil
              end
            when 'secure'
              cookie.secure = true
            when 'httponly'
              cookie.httponly = true
            end
          end

          cookie.secure   ||= false
          cookie.httponly ||= false

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
        }
      }
    end
  end

  # Sets the cookie name.
  def name=(name)
    if name.nil? || name.empty?
      raise ArgumentError, "cookie name cannot be empty"
    elsif name.match(/[\x00-\x1F=\x7F]/)
      raise ArgumentError, "cookie name cannot contain a control character or an equal sign"
    end
    @name = name
  end

  # Sets the domain attribute.  A leading dot in +domain+ implies
  # turning the +for_domain?+ flag on.
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

  # Sets the path attribute value.
  def path=(path)
    @path = HTTP::Cookie.normalize_path(path)
  end

  # Sets the origin of the cookie.  This initializes the `domain` and
  # `path` attribute values if unknown yet.
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

  # Sets the Expires attribute value, accepting a `Time` object, a
  # string representation of date/time, or `nil`.
  #
  # Note that max_age and expires are mutually exclusive.  Setting
  # `max_age` resets `expires` to nil, and vice versa.
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

  attr_reader :max_age

  # Sets the Max-Age attribute, accepting an integer, or a string-like
  # that represents an integer which will be stringified and then
  # integerized using #to_i.
  #
  # Note that max_age and expires are mutually exclusive.  Setting
  # `max_age` resets `expires` to nil, and vice versa.
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
  def expire
    self.expires = UNIX_EPOCH
    self
  end

  alias secure? secure
  alias httponly? httponly
  alias session? session

  # Tests if it is OK to accept this cookie if it is sent from a given
  # +uri.
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

  # Tests if it is OK to send this cookie to a given +uri+, A runtime
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

    string = cookie_value
    if @for_domain || @domain != DomainName.new(origin.host).hostname
      string << "; domain=#{@domain}"
    end
    if (HTTP::Cookie.normalize_path(origin) + './').path != @path
      string << "; path=#{@path}"
    end
    if @max_age
      string << "; Max-Age=#{@max_age}"
    elsif @expires
      string << "; Expires=#{@expires.httpdate}"
    end
    if @comment
      string << "; comment=#{@comment}"
    end
    if @httponly
      string << "; HttpOnly"
    end
    if @secure
      string << "; secure"
    end
    string
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
        send(:"#{key}=", value)
      end
    }
  end
end
