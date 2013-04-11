# :markup: markdown
require 'http/cookie'

##
# This class is used to manage the Cookies that have been returned from
# any particular website.

class HTTP::CookieJar
  require 'http/cookie_jar/abstract_store'
  require 'http/cookie_jar/abstract_saver'

  attr_reader :store

  # Generates a new cookie jar.
  #
  # Available option keywords are as below:
  #
  # :store
  # : The store class that backs this jar. (default: `:hash`)
  # A symbol or an instance of a store class is accepted.  Symbols are
  # mapped to store classes, like `:hash` to
  # HTTP::CookieJar::HashStore and `:mozilla` to
  # HTTP::CookieJar::MozillaStore.
  #
  # Any options given are passed through to the initializer of the
  # specified store class.  For example, the `:mozilla`
  # (HTTP::CookieJar::MozillaStore) store class requires a `:filename`
  # option.  See individual store classes for details.
  def initialize(options = nil)
    opthash = {
      :store => :hash,
    }
    opthash.update(options) if options
    case store = opthash[:store]
    when Symbol
      @store = AbstractStore.implementation(store).new(opthash)
    when AbstractStore
      @store = store
    else
      raise TypeError, 'wrong object given as cookie store: %s' % store.inspect
    end
  end

  def initialize_copy(other)
    @store = other.instance_eval { @store.dup }
  end

  # Adds a cookie to the jar if it is acceptable, and returns self in
  # any case.  A given cookie must have domain and path attributes
  # set, or ArgumentError is raised.
  #
  # Whether a cookie with the `for_domain` flag on overwrites another
  # with the flag off or vice versa depends on the store used.  See
  # individual store classes for that matter.
  #
  # ### Compatibility Note for Mechanize::Cookie users
  #
  # In HTTP::Cookie, each cookie object can store its origin URI
  # (cf. #origin).  While the origin URI of a cookie can be set
  # manually by #origin=, one is typically given in its generation.
  # To be more specific, HTTP::Cookie.new takes an `:origin` option
  # and HTTP::Cookie.parse takes one via the second argument.
  #
  #       # Mechanize::Cookie
  #       jar.add(origin, cookie)
  #       jar.add!(cookie)    # no acceptance check is performed
  #
  #       # HTTP::Cookie
  #       jar.origin = origin
  #       jar.add(cookie)     # acceptance check is performed
  def add(cookie)
    @store.add(cookie) if cookie.acceptable?
    self
  end
  alias << add

  # Deletes a cookie that has the same name, domain and path as a
  # given cookie from the jar and returns self.
  #
  # How the `for_domain` flag value affects the set of deleted cookies
  # depends on the store used.  See individual store classes for that
  # matter.
  def delete(cookie)
    @store.delete(cookie)
    self
  end

  # Gets an array of cookies that should be sent for the URL/URI,
  # updating the access time of each cookie.
  def cookies(url)
    now = Time.now
    each(url).reject(&:expired?).sort
  end

  # Tests if the jar is empty.  If `url` is given, tests if there is
  # no cookie for the URL.
  def empty?(url = nil)
    if url
      each(url) { return false }
      return true
    else
      @store.empty?
    end
  end

  # Iterates over all cookies that are not expired in no particular
  # order.
  #
  # An optional argument `uri` specifies a URI/URL indicating the
  # destination of the cookies being selected.  Every cookie yielded
  # should be good to send to the given URI,
  # i.e. cookie.valid_for_uri?(uri) evaluates to true.
  #
  # If (and only if) the `uri` option is given, last access time of
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

  # Parses a Set-Cookie field value `set_cookie` sent from a URI
  # `origin` and adds the cookies parsed as valid to the jar.  Returns
  # an array of cookies that have been added.  If a block is given, it
  # is called after each cookie is added.
  #
  # `jar.parse(set_cookie, origin)` is a shorthand for this:
  #
  #         HTTP::Cookie.parse(set_cookie, origin) { |cookie|
  #           jar.add(cookie)
  #         }
  #
  # See HTTP::Cookie.parse for available options.
  def parse(set_cookie, origin, options = nil) # :yield: cookie
    if block_given?
      HTTP::Cookie.parse(set_cookie, origin, options) { |cookie|
        add(cookie)
        yield cookie
      }
    else
      HTTP::Cookie.parse(set_cookie, origin, options) { |cookie|
        add(cookie)
      }
      # XXX: ruby 1.8 fails to call super from a proc'ized method
      # HTTP::Cookie.parse(set_cookie, origin, options, &method(:add)
    end
  end

  # call-seq:
  #   jar.save(filename_or_io, **options)
  #   jar.save(filename_or_io, format = :yaml, **options)
  #
  # Saves the cookie jar into a file or an IO in the format specified
  # and returns self.  If a given object responds to #write it is
  # taken as an IO, or taken as a filename otherwise.
  #
  # Available option keywords are below:
  #
  # * `:format`
  #
  #     <dl class="rdoc-list note-list">
  #       <dt>:yaml</dt>
  #       <dd>YAML structure (default)</dd>
  #       <dt>:cookiestxt</dt>
  #       <dd>: Mozilla's cookies.txt format</dd>
  #     </dl>
  #
  # * `:session`
  #
  #     <dl class="rdoc-list note-list">
  #       <dt>true</dt>
  #       <dd>Save session cookies as well.</dd>
  #       <dt>false</dt>
  #       <dd>Do not save session cookies. (default)</dd>
  #     </dl>
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
  # into the jar and returns self.  If a given object responds to
  # \#read it is taken as an IO, or taken as a filename otherwise.
  #
  # Available option keywords are below:
  #
  # * `:format`
  #
  #     <dl class="rdoc-list note-list">
  #       <dt>:yaml</dt>
  #       <dd>YAML structure (default)</dd>
  #       <dt>:cookiestxt</dt>
  #       <dd>Mozilla's cookies.txt format</dd>
  #     </dl>
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

  # Clears the cookie jar and returns self.
  def clear
    @store.clear
    self
  end

  # Removes expired cookies and returns self.
  def cleanup(session = false)
    @store.cleanup session
    self
  end
end
