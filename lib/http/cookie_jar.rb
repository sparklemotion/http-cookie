require 'http/cookie'

##
# This class is used to manage the Cookies that have been returned from
# any particular website.

class HTTP::CookieJar
  require 'http/cookie_jar/abstract_store'
  require 'http/cookie_jar/abstract_saver'

  attr_reader :store

  # Generates a new cookie jar.  The default store class is `:hash`,
  # which maps to `HTTP::CookieJar::HashStore`.  Any given options are
  # passed through to the initializer of the specified store class.
  def initialize(store = :hash, options = nil)
    case store
    when Symbol
      @store = AbstractStore.implementation(store).new(options)
    when AbstractStore
      options.empty? or
        raise ArgumentError, 'wrong number of arguments (%d for 1)' % (1 + options.size)
      @store = store
    else
      raise TypeError, 'wrong object given as cookie store: %s' % store.inspect
    end
  end

  def initialize_copy(other)
    @store = other.instance_eval { @store.dup }
  end

  # Adds a +cookie+ to the jar and return self.  If a given cookie has
  # no domain or path attribute values and the origin is unknown,
  # ArgumentError is raised.
  #
  # ### Compatibility Note for Mechanize::Cookie users
  #
  # In HTTP::Cookie, each cookie object can store its origin URI
  # (cf. #origin).  While the origin URI of a cookie can be set
  # manually by #origin=, one is typically given in its generation.
  # To be more specific, HTTP::Cookie.new and HTTP::Cookie.parse both
  # take an :origin option.
  #
  #   `HTTP::Cookie.parse`.  Compare these:
  #
  #       # Mechanize::Cookie
  #       jar.add(origin, cookie)
  #       jar.add!(cookie)    # no acceptance check is performed
  #
  #       # HTTP::Cookie
  #       jar.origin = origin # if it doesn't have one
  #       jar.add(cookie)     # acceptance check is performed
  def add(cookie)
    if cookie.domain.nil? || cookie.path.nil?
      raise ArgumentError, "a cookie with unknown domain or path cannot be added"
    end

    @store.add(cookie)
    self
  end
  alias << add

  # Gets an array of cookies that should be sent for the URL/URI.
  def cookies(url)
    now = Time.now
    each(url).select { |cookie|
      !cookie.expired? && (cookie.accessed_at = now)
    }.sort
  end

  # Tests if the jar is empty.  If +url+ is given, tests if there is
  # no cookie for the URL.
  def empty?(url = nil)
    if url
      each(url) { return false }
      return true
    else
      @store.empty?
    end
  end

  # Iterates over all cookies that are not expired.
  #
  # An optional argument +uri+ specifies a URI/URL indicating the
  # destination of the cookies being selected.  Every cookie yielded
  # should be good to send to the given URI,
  # i.e. cookie.valid_for_uri?(uri) evaluates to true.
  #
  # If (and only if) the +uri+ option is given, last access time of
  # each cookie is updated to the current time.
  def each(uri = nil, &block)
    block_given? or return enum_for(__method__, uri)

    if uri
      uri = URI(uri)
      return self unless URI::HTTP === uri && uri.host
    end

    @store.each(uri, &block)
    self
  end
  include Enumerable

  # call-seq:
  #   jar.save(filename_or_io, **options)
  #   jar.save(filename_or_io, format = :yaml, **options)
  #
  # Saves the cookie jar into a file or an IO in the format specified
  # and return self.  If a given object responds to #write it is taken
  # as an IO, or taken as a filename otherwise.
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
    rescue IndexError => e
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

  # call-seq:
  #   jar.load(filename_or_io, **options)
  #   jar.load(filename_or_io, format = :yaml, **options)
  #
  # Loads cookies recorded in a file or an IO in the format specified
  # into the jar and return self.  If a given object responds to #read
  # it is taken as an IO, or taken as a filename otherwise.
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
    rescue IndexError => e
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

  # Clears the cookie jar and return self.
  def clear
    @store.clear
    self
  end

  # Removes expired cookies and return self.
  def cleanup(session = false)
    @store.cleanup session
    self
  end
end
