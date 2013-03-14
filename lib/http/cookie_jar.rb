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

    path_cookies = ((@jar[normal_domain] ||= {})[cookie.path] ||= {})

    if cookie.expired?
      path_cookies.delete(cookie.name)
    else
      path_cookies[cookie.name] = cookie
    end

    self
  end
  alias << add

  # Fetch the cookies that should be used for the URL/URI.
  def cookies(url)
    now = Time.now
    each(url).select { |cookie|
      !cookie.expired? && (cookie.accessed_at = now)
    }.sort
  end

  # Tests if the jar is empty.  If url is given, tests if there is no
  # cookie for the URL.
  def empty?(url = nil)
    if url
      each(url) { return false }
      return true
    else
      @jar.empty?
    end
  end

  # Iterate over cookies.  If +uri+ is given, cookies not for the
  # URL/URI are excluded.
  def each(uri = nil, &block)
    block_given? or return enum_for(__method__, uri)

    if uri
      block = proc { |cookie|
        yield cookie if cookie.valid_for_uri?(uri)
      }
    end

    @jar.each { |domain, paths|
      paths.each { |path, hash|
        hash.each_value(&block)
      }
    }
    self
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
        require_yaml

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
    File.open(file) { |f|
      case format
      when :yaml then
        require_yaml
        @jar = YAML.load(f)
      when :cookiestxt then
        load_cookiestxt(f)
      else
        raise ArgumentError, "Unknown cookie jar file format"
      end
    }

    cleanup
  end

  def require_yaml # :nodoc:
    begin
      require 'psych'
    rescue LoadError
    end

    require 'yaml'
  end
  private :require_yaml

  # Clear the cookie jar and return self.
  def clear
    @jar.clear
    self
  end

  # Read cookies from Mozilla cookies.txt-style IO stream and return
  # self.
  def load_cookiestxt(io)
    io.each_line do |line|
      c = HTTP::Cookie.parse_cookiestxt_line(line) and add(c)
    end

    self
  end

  # Write cookies to Mozilla cookies.txt-style IO stream and return
  # self.
  def dump_cookiestxt(io)
    io.puts "# HTTP Cookie File"
    to_a.each do |cookie|
      io.print cookie.to_cookiestxt_line
    end
    self
  end

  protected

  # Remove expired cookies and return self.
  def cleanup session = false
    @jar.each do |domain, paths|
      paths.each do |path, hash|
        hash.delete_if { |cookie_name, cookie|
          cookie.expired? || (session && cookie.session?)
        }
      end
    end
    self
  end
end

