require 'http/cookie'

##
# This class is used to manage the Cookies that have been returned from
# any particular website.

class HTTP::CookieJar
  autoload :AbstractSaver, 'http/cookie_jar/abstract_saver'
  autoload :AbstractStore, 'http/cookie_jar/abstract_store'

  attr_reader :store

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

  # Add a +cookie+ to the jar and return self.
  def add(cookie)
    if cookie.domain.nil? || cookie.path.nil?
      raise ArgumentError, "a cookie with unknown domain or path cannot be added"
    end

    @store.add(cookie)
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
      @store.empty?
    end
  end

  # Iterates over all cookies that are not expired.
  #
  # Available option keywords are below:
  #
  # * +uri+
  #
  #   Specify a URI/URL indicating the destination of the cookies
  #   being selected.  Every cookie yielded should be good to send to
  #   the given URI, i.e. cookie.valid_for_uri?(uri) evaluates to
  #   true.
  #
  #   If (and only if) this option is given, last access time of each
  #   cookie is updated to the current time.
  def each(uri = nil, &block)
    block_given? or return enum_for(__method__, uri)

    if uri
      block = proc { |cookie|
        yield cookie if cookie.valid_for_uri?(uri)
      }
    end

    @store.each(uri, &block)
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
    @store.clear
    self
  end

  # Remove expired cookies and return self.
  def cleanup(session = false)
    @store.cleanup session
    self
  end
end
