module HTTP
  autoload :Cookie, 'http/cookie'
end

##
# This class is used to manage the Cookies that have been returned from
# any particular website.

class HTTP::CookieJar
  autoload :AbstractSaver, 'http/cookie_jar/abstract_saver'

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
  include Enumerable

  # call-seq:
  #   jar.save(filename_or_io, **options)
  #   jar.save(filename_or_io, format = :yaml, **options)
  #
  # Save the cookie jar into a file or an IO in the format specified
  # and return self.  If the given object responds to #write it is
  # taken as an IO, or taken as a filename otherwise.
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
  #
  # All options given are passed through to the underlying cookie
  # saver module.
  def save(writable, *options)
    opthash = {
      :format => :yaml,
      :session => false,
    }
    case options.size
    when 0
    when 1
      case options = options.first
      when Symbol
        opthash[:format] = options
      else
        opthash.update(options) if options
      end
    when 2
      opthash[:format], options = options
      opthash.update(options) if options
    else
      raise ArgumentError, 'wrong number of arguments (%d for 1-3)' % (1 + options.size)
    end

    begin
      saver = AbstractSaver.implementation(opthash[:format]).new(opthash)
    rescue KeyError => e
      raise ArgumentError, e.message
    end

    if writable.respond_to?(:write)
      saver.save(writable, self)
    else
      File.open(writable, 'w') { |io|
        saver.save(io, self)
      }
    end

    self
  end

  # An obsolete name for save().
  def save_as(*args)
    warn "%s() is obsolete; use save()." % __method__
    save(*args)
  end

  # call-seq:
  #   jar.load(filename_or_io, **options)
  #   jar.load(filename_or_io, format = :yaml, **options)
  #
  # Load cookies recorded in a file or an IO in the format specified
  # into the jar and return self.  If the given object responds to
  # #read it is taken as an IO, or taken as a filename otherwise.
  #
  # Available option keywords are below:
  #
  # * +format+
  #   [<tt>:yaml</tt>]
  #     YAML structure (default)
  #   [<tt>:cookiestxt</tt>]
  #     Mozilla's cookies.txt format
  #
  # All options given are passed through to the underlying cookie
  # saver module.
  def load(readable, *options)
    opthash = {
      :format => :yaml,
      :session => false,
    }
    case options.size
    when 0
    when 1
      case options = options.first
      when Symbol
        opthash[:format] = options
      else
        opthash.update(options) if options
      end
    when 2
      opthash[:format], options = options
      opthash.update(options) if options
    else
      raise ArgumentError, 'wrong number of arguments (%d for 1-3)' % (1 + options.size)
    end

    begin
      saver = AbstractSaver.implementation(opthash[:format]).new(opthash)
    rescue KeyError => e
      raise ArgumentError, e.message
    end

    if readable.respond_to?(:write)
      saver.load(readable, self)
    else
      File.open(readable, 'r') { |io|
        saver.load(io, self)
      }
    end

    self
  end

  # Clear the cookie jar and return self.
  def clear
    @jar.clear
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

