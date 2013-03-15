require 'http/cookie_jar'

class HTTP::CookieJar::AbstractStore
  class << self
    @@class_map = {}

    # Gets an implementation class by the name, optionally trying to
    # load "http/cookie_jar/*_store" if not found.  If loading fails,
    # KeyError is raised.
    def implementation(symbol)
      @@class_map.fetch(symbol)
    rescue KeyError
      begin
        require 'http/cookie_jar/%s_store' % symbol
        @@class_map.fetch(symbol)
      rescue LoadError, KeyError => e
        raise KeyError, 'cookie store unavailable: %s' % symbol.inspect
      end
    end

    def inherited(subclass)
      @@class_map[class_to_symbol(subclass)] = subclass
    end

    def class_to_symbol(klass)
      klass.name[/[^:]+?(?=Store$|$)/].downcase.to_sym
    end
  end

  def default_options
    {}
  end
  private :default_options

  def initialize(options = nil)
    options ||= {}
    @logger = options[:logger]
    # Initializes each instance variable of the same name as option
    # keyword.
    default_options.each_pair { |key, default|
      instance_variable_set("@#{key}", options.key?(key) ? options[key] : default)
    }
  end

  def initialize_copy(other)
    raise
    self
  end

  def add(cookie)
    raise
    self
  end

  # Iterates over all cookies that are not expired.
  #
  # Available option keywords are below:
  #
  # * +uri+
  #
  #   Specify a URI object indicating the destination of the cookies
  #   being selected.  Every cookie yielded should be good to send to
  #   the given URI, i.e. cookie.valid_for_uri?(uri) evaluates to
  #   true.
  #
  #   If (and only if) this option is given, last access time of each
  #   cookie is updated to the current time.
  def each(options = nil, &block)
    raise
    self
  end
  include Enumerable

  def empty?
    raise
  end

  def clear
    raise
    self
  end

  def cleanup(session = false)
    if session
      select { |cookie| cookie.session? || cookie.expired? }
    else
      select(&:expired?)
    end.each { |cookie|
      add(cookie.expire)
    }
    # subclasses can optionally remove over-the-limit cookies.
    self
  end
end
