require 'http/cookie/version'
require 'time'
require 'webrick/httputils'
require 'domain_name'

module HTTP
  autoload :CookieJar, 'http/cookie_jar'
end

# This class is used to represent an HTTP Cookie.
class HTTP::Cookie
  # In Ruby < 1.9.3 URI() does not accept an URI object.
  if RUBY_VERSION < "1.9.3"
    module URIFix
      def URI(url)
        url.is_a?(URI) ? url : Kernel::URI(url)
      end
      private :URI
    end
  end

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

  include URIFix if defined?(URIFix)

  attr_reader :name
  attr_accessor :value, :version
  attr_accessor :domain, :path, :secure
  attr_accessor :comment, :max_age

  attr_accessor :session

  attr_accessor :created_at
  attr_accessor :accessed_at

  attr_accessor :origin

  # :call-seq:
  #     new(name, value)
  #     new(name, value, attr_hash)
  #     new(attr_hash)
  #
  # Creates a cookie object.  For each key of +attr_hash+, the setter
  # is called if defined.  Each key can be either a symbol or a
  # string, downcased or not.
  #
  # e.g.
  #     new("uid", "a12345")
  #     new("uid", "a12345", :domain => 'example.org',
  #                          :for_domain => true, :expired => Time.now + 7*86400)
  #     new("name" => "uid", "value" => "a12345", "Domain" => 'www.example.org')
  #
  def initialize(*args)
    @version = 0     # Netscape Cookie

    @domain = @path = @secure = @comment = @max_age =
      @expires = @comment_url = @discard = @port = nil

    @created_at = @accessed_at = Time.now
    case args.size
    when 2
      @name, @value = *args
      @for_domain = false
      return
    when 3
      @name, @value, attr_hash = *args
    when 1
      attr_hash = args.first
    else
      raise ArgumentError, "wrong number of arguments (#{args.size} for 1-3)"
    end
    for_domain = false
    attr_hash.each_pair { |key, val|
      skey = key.to_s.downcase
      if skey.sub!(/\?\z/, '')
        val = val ? true : false
      end
      case skey
      when 'for_domain'
        for_domain = !!val
      when 'name'
        @name = val
      when 'value'
        @value = val
      else
        setter = :"#{skey}="
        send(setter, val) if respond_to?(setter)
      end
    }
    @for_domain = for_domain
  end

  # If this flag is true, this cookie will be sent to any host in the
  # +domain+.  If it is false, this cookie will be sent only to the
  # host indicated by the +domain+.
  attr_accessor :for_domain
  alias for_domain? for_domain

  class << self
    include URIFix if defined?(URIFix)

    # Parses a Set-Cookie header value +set_cookie+ into an array of
    # Cookie objects.  Parts (separated by commas) that are malformed
    # are ignored.
    #
    # If a block is given, each cookie object is passed to the block.
    #
    # The cookie's origin URI/URL and a logger object can be passed in
    # +options+ with the keywords +:origin+ and +:logger+,
    # respectively.
    def parse(set_cookie, options = nil, &block)
      if options
        logger = options[:logger]
        origin = options[:origin] and origin = URI(origin)
      end

      [].tap { |cookies|
        set_cookie.split(/,(?=[^;,]*=)|,$/).each { |c|
          cookie_elem = c.split(/;+/)
          first_elem = cookie_elem.shift
          first_elem.strip!
          key, value = first_elem.split(/\=/, 2)

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
            value = WEBrick::HTTPUtils.dequote(value.strip) if value

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
              next unless value && !value.empty?
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
            end
          end

          cookie.secure  ||= false

          # RFC 6265 4.1.2.2
          cookie.expires   = Time.now + cookie.max_age if cookie.max_age
          cookie.session   = !cookie.expires

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

  def origin=(origin)
    @origin.nil? or
      raise ArgumentError, "origin cannot be changed once it is set"
    origin = URI(origin)
    acceptable_from_uri?(origin) or
      raise ArgumentError, "unacceptable cookie sent from URI #{origin}"
    self.domain ||= origin.host
    self.path   ||= (origin + './').path
    @origin = origin
  end

  def expires=(t)
    @expires = t && (t.is_a?(Time) ? t.httpdate : t.to_s)
  end

  def expires
    @expires && Time.parse(@expires)
  end

  def expired?
    return false unless expires
    Time.now > expires
  end

  alias secure? secure

  def acceptable_from_uri?(uri)
    uri = URI(uri)
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

  def valid_for_uri?(uri)
    uri = URI(uri)
    if @domain.nil?
      raise "cannot tell if this cookie is valid because the domain is unknown"
    end
    return false if secure? && uri.scheme != 'https'
    acceptable_from_uri?(uri) && uri.path.start_with?(@path)
  end

  def to_s
    "#{@name}=#{@value}"
  end

  def init_with(coder)
    yaml_initialize(coder.tag, coder.map)
  end

  def yaml_initialize(tag, map)
    @for_domain = true    # for forward compatibility
    map.each { |key, value|
      case key
      when 'domain'
        self.domain = value # ditto
      else
        instance_variable_set(:"@#{key}", value)
      end
    }
  end
end
