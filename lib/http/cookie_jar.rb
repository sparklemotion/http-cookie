module HTTP
  autoload :Cookie, 'http/cookie'
end

##
# This class is used to manage the Cookies that have been returned from
# any particular website.

class HTTP::CookieJar
  include Enumerable

  attr_reader :jar

  def initialize
    @jar = {}
  end

  def initialize_copy other # :nodoc:
    @jar = Marshal.load Marshal.dump other.jar
  end

  # Add a +cookie+ to the jar and return self.
  def add(cookie)
    if cookie.domain.nil? || cookie.path.nil?
      raise ArgumentError, "a cookie with unknown domain or path cannot be added"
    end
    normal_domain = cookie.domain_name.hostname

    ((@jar[normal_domain] ||= {})[cookie.path] ||= {})[cookie.name] = cookie

    self
  end
  alias << add

  # Fetch the cookies that should be used for the URI object passed in.
  def cookies(url)
    now = Time.now
    select { |cookie|
      !cookie.expired? && cookie.valid_for_uri?(url) && (cookie.accessed_at = now)
    }.sort
  end

  def empty?(url)
    cookies(url).empty?
  end

  def each
    block_given? or return enum_for(__method__)
    cleanup
    @jar.each { |domain, paths|
      paths.each { |path, hash|
        hash.each_value { |cookie|
          yield cookie
        }
      }
    }
  end

  # call-seq:
  #   jar.save_as(file, format = :yaml)
  #   jar.save_as(file, options)
  #
  # Save the cookie jar to a file in the format specified and return
  # self.
  #
  # Available option keywords are below:
  #
  # * +format+
  #   [<tt>:yaml</tt>]
  #     YAML structure (default)
  #   [<tt>:cookiestxt</tt>]
  #     Mozilla's cookies.txt format
  # * +session+
  #   [+true+]
  #     Save session cookies as well.
  #   [+false+]
  #     Do not save session cookies. (default)
  def save_as(file, options = nil)
    if Symbol === options
      format = options
      session = false
    else
      options ||= {}
      format = options[:format] || :yaml
      session = !!options[:session]
    end

    jar = dup
    jar.cleanup !session

    open(file, 'w') { |f|
      case format
      when :yaml then
        load_yaml

        YAML.dump(jar.jar, f)
      when :cookiestxt then
        jar.dump_cookiestxt(f)
      else
        raise ArgumentError, "Unknown cookie jar file format"
      end
    }

    self
  end

  # Load cookie jar from a file in the format specified.
  #
  # Available formats:
  # :yaml  <- YAML structure.
  # :cookiestxt  <- Mozilla's cookies.txt format
  def load(file, format = :yaml)
    @jar = open(file) { |f|
      case format
      when :yaml then
        load_yaml

        YAML.load(f)
      when :cookiestxt then
        load_cookiestxt(f)
      else
        raise ArgumentError, "Unknown cookie jar file format"
      end
    }

    cleanup

    self
  end

  def load_yaml # :nodoc:
    begin
      require 'psych'
    rescue LoadError
    end

    require 'yaml'
  end

  # Clear the cookie jar
  def clear
    @jar = {}
  end

  # Read cookies from Mozilla cookies.txt-style IO stream
  def load_cookiestxt(io)
    now = Time.now

    io.each_line do |line|
      c = HTTP::Cookie.parse_cookiestxt_line(line) and add(c)
    end

    @jar
  end

  # Write cookies to Mozilla cookies.txt-style IO stream
  def dump_cookiestxt(io)
    to_a.each do |cookie|
      io.print cookie.to_cookiestxt_line
    end
  end

  protected

  # Remove expired cookies
  def cleanup session = false
    @jar.each do |domain, paths|
      paths.each do |path, names|
        names.each do |cookie_name, cookie|
          paths[path].delete(cookie_name) if
            cookie.expired? or (session and cookie.session)
        end
      end
    end
  end
end

