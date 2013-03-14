require 'http/cookie_jar'

# CookiestxtSaver saves and loads cookies in the cookies.txt format.
class HTTP::CookieJar::CookiestxtSaver < HTTP::CookieJar::AbstractSaver
  True  = "TRUE"
  False = "FALSE"

  def save(io, jar)
    io.puts @header if @header
    jar.each { |cookie|
      next if !@session && cookie.session?
      io.print cookie_to_record(cookie)
    }
  end

  def load(io, jar)
    io.each_line { |line|
      cookie = parse_record(line) and jar.add(cookie)
    }
  end

  private

  def default_options
    {
      header: "# HTTP Cookie File",
      linefeed: "\n",
    }
  end

  # Serializes the cookie into a cookies.txt line.
  def cookie_to_record(cookie)
    cookie.instance_eval {
      [
        @domain,
        @for_domain ? True : False,
        @path,
        @secure ? True : False,
        @expires.to_i,
        @name,
        @value
      ]
    }.join("\t") << @linefeed
  end

  # Parses a line from cookies.txt and returns a cookie object if the
  # line represents a cookie record or returns nil otherwise.
  def parse_record(line)
    return nil if line.match(/^#/)

    domain,
    s_for_domain,	# Whether this cookie is for domain
    path,		# Path for which the cookie is relevant
    s_secure,		# Requires a secure connection
    s_expires,		# Time the cookie expires (Unix epoch time)
    name, value = line.split("\t", 7)
    return nil if value.nil?

    value.chomp!

    if (expires_seconds = s_expires.to_i).nonzero?
      expires = Time.at(expires_seconds)
      return nil if expires < Time.now
    end

    HTTP::Cookie.new(name, value,
      :domain => domain,
      :for_domain => s_for_domain == True,
      :path => path,
      :secure => s_secure == True,
      :expires => expires,
      :version => 0)
  end
end
