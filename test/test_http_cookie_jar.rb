require File.expand_path('helper', File.dirname(__FILE__))

class TestHTTPCookieJar < Test::Unit::TestCase
  def setup
    @jar = HTTP::CookieJar.new
  end

  def in_tmpdir
    Dir.mktmpdir do |dir|
      Dir.chdir dir do
        yield
      end
    end
  end

  def cookie_values(options = {})
    {
      :name     => 'Foo',
      :value    => 'Bar',
      :path     => '/',
      :expires  => Time.now + (10 * 86400),
      :for_domain => true,
      :domain   => 'rubyforge.org',
      :origin   => 'http://rubyforge.org/'
   }.merge(options)
  end

  def test_two_cookies_same_domain_and_name_different_paths
    url = URI 'http://rubyforge.org/'

    cookie = HTTP::Cookie.new(cookie_values)
    @jar.add(cookie)
    @jar.add(HTTP::Cookie.new(cookie_values(:path => '/onetwo')))

    assert_equal(1, @jar.cookies(url).length)
    assert_equal 2, @jar.cookies(URI('http://rubyforge.org/onetwo')).length
  end

  def test_domain_case
    url = URI 'http://rubyforge.org/'

    # Add one cookie with an expiration date in the future
    cookie = HTTP::Cookie.new(cookie_values)
    @jar.add(cookie)
    assert_equal(1, @jar.cookies(url).length)

    @jar.add(HTTP::Cookie.new(cookie_values(:domain => 'RuByForge.Org', :name => 'aaron')))

    assert_equal(2, @jar.cookies(url).length)

    url2 = URI 'http://RuByFoRgE.oRg/'
    assert_equal(2, @jar.cookies(url2).length)
  end

  def test_host_only
    url = URI.parse('http://rubyforge.org/')

    @jar.add(HTTP::Cookie.new(
        cookie_values(:domain => 'rubyforge.org', :for_domain => false)))

    assert_equal(1, @jar.cookies(url).length)

    assert_equal(1, @jar.cookies(URI('http://RubyForge.org/')).length)

    assert_equal(1, @jar.cookies(URI('https://RubyForge.org/')).length)

    assert_equal(0, @jar.cookies(URI('http://www.rubyforge.org/')).length)
  end

  def test_empty_value
    url = URI 'http://rubyforge.org/'
    values = cookie_values(:value => "")

    # Add one cookie with an expiration date in the future
    cookie = HTTP::Cookie.new(values)
    @jar.add(cookie)
    assert_equal(1, @jar.cookies(url).length)

    @jar.add HTTP::Cookie.new(values.merge(:domain => 'RuByForge.Org',
                                           :name   => 'aaron'))

    assert_equal(2, @jar.cookies(url).length)

    url2 = URI 'http://RuByFoRgE.oRg/'
    assert_equal(2, @jar.cookies(url2).length)
  end

  def test_add_future_cookies
    url = URI 'http://rubyforge.org/'

    # Add one cookie with an expiration date in the future
    cookie = HTTP::Cookie.new(cookie_values)
    @jar.add(cookie)
    assert_equal(1, @jar.cookies(url).length)

    # Add the same cookie, and we should still only have one
    @jar.add(HTTP::Cookie.new(cookie_values))
    assert_equal(1, @jar.cookies(url).length)

    # Make sure we can get the cookie from different paths
    assert_equal(1, @jar.cookies(URI('http://rubyforge.org/login')).length)

    # Make sure we can't get the cookie from different domains
    assert_equal(0, @jar.cookies(URI('http://google.com/')).length)
  end

  def test_add_multiple_cookies
    url = URI 'http://rubyforge.org/'

    # Add one cookie with an expiration date in the future
    cookie = HTTP::Cookie.new(cookie_values)
    @jar.add(cookie)
    assert_equal(1, @jar.cookies(url).length)

    # Add the same cookie, and we should still only have one
    @jar.add(HTTP::Cookie.new(cookie_values(:name => 'Baz')))
    assert_equal(2, @jar.cookies(url).length)

    # Make sure we can get the cookie from different paths
    assert_equal(2, @jar.cookies(URI('http://rubyforge.org/login')).length)

    # Make sure we can't get the cookie from different domains
    assert_equal(0, @jar.cookies(URI('http://google.com/')).length)
  end

  def test_add_multiple_cookies_with_the_same_name
    now = Time.now

    cookies = [
      { :value => 'a', :path => '/', },
      { :value => 'b', :path => '/abc/def/', :created_at => now - 1 },
      { :value => 'c', :path => '/abc/def/', :domain => 'www.rubyforge.org', :origin => 'http://www.rubyforge.org/abc/def/', :created_at => now },
      { :value => 'd', :path => '/abc/' },
    ].map { |attrs|
      HTTP::Cookie.new(cookie_values(attrs))
    }

    url = URI 'http://www.rubyforge.org/abc/def/ghi'

    cookies.permutation(cookies.size) { |shuffled|
      @jar.clear
      shuffled.each { |cookie| @jar.add(cookie) }
      assert_equal %w[b c d a], @jar.cookies(url).map { |cookie| cookie.value }
    }
  end

  def test_fall_back_rules_for_local_domains
    url = URI 'http://www.example.local'

    sld_cookie = HTTP::Cookie.new(cookie_values(:domain => '.example.local', :origin => url))
    @jar.add(sld_cookie)

    assert_equal(1, @jar.cookies(url).length)
  end

  def test_add_makes_exception_for_localhost
    url = URI 'http://localhost'

    tld_cookie = HTTP::Cookie.new(cookie_values(:domain => 'localhost', :origin => url))
    @jar.add(tld_cookie)

    assert_equal(1, @jar.cookies(url).length)
  end

  def test_add_cookie_for_the_parent_domain
    url = URI 'http://x.foo.com'

    cookie = HTTP::Cookie.new(cookie_values(:domain => '.foo.com', :origin => url))
    @jar.add(cookie)

    assert_equal(1, @jar.cookies(url).length)
  end

  def test_add_rejects_cookies_with_unknown_domain_or_path
    cookie = HTTP::Cookie.new(cookie_values.reject { |k,v| [:origin, :domain].include?(k) })
    assert_raises(ArgumentError) {
      @jar.add(cookie)
    }

    cookie = HTTP::Cookie.new(cookie_values.reject { |k,v| [:origin, :path].include?(k) })
    assert_raises(ArgumentError) {
      @jar.add(cookie)
    }
  end

  def test_add_does_not_reject_cookies_from_a_nested_subdomain
    url = URI 'http://y.x.foo.com'

    cookie = HTTP::Cookie.new(cookie_values(:domain => '.foo.com', :origin => url))
    @jar.add(cookie)

    assert_equal(1, @jar.cookies(url).length)
  end

  def test_cookie_without_leading_dot_does_not_cause_substring_match
    url = URI 'http://arubyforge.org/'

    cookie = HTTP::Cookie.new(cookie_values(:domain => 'rubyforge.org'))
    @jar.add(cookie)

    assert_equal(0, @jar.cookies(url).length)
  end

  def test_cookie_without_leading_dot_matches_subdomains
    url = URI 'http://admin.rubyforge.org/'

    cookie = HTTP::Cookie.new(cookie_values(:domain => 'rubyforge.org', :origin => url))
    @jar.add(cookie)

    assert_equal(1, @jar.cookies(url).length)
  end

  def test_cookies_with_leading_dot_match_subdomains
    url = URI 'http://admin.rubyforge.org/'

    @jar.add(HTTP::Cookie.new(cookie_values(:domain => '.rubyforge.org', :origin => url)))

    assert_equal(1, @jar.cookies(url).length)
  end

  def test_cookies_with_leading_dot_match_parent_domains
    url = URI 'http://rubyforge.org/'

    @jar.add(HTTP::Cookie.new(cookie_values(:domain => '.rubyforge.org', :origin => url)))

    assert_equal(1, @jar.cookies(url).length)
  end

  def test_cookies_with_leading_dot_match_parent_domains_exactly
    url = URI 'http://arubyforge.org/'

    @jar.add(HTTP::Cookie.new(cookie_values(:domain => '.rubyforge.org')))

    assert_equal(0, @jar.cookies(url).length)
  end

  def test_cookie_for_ipv4_address_matches_the_exact_ipaddress
    url = URI 'http://192.168.0.1/'

    cookie = HTTP::Cookie.new(cookie_values(:domain => '192.168.0.1', :origin => url))
    @jar.add(cookie)

    assert_equal(1, @jar.cookies(url).length)
  end

  def test_cookie_for_ipv6_address_matches_the_exact_ipaddress
    url = URI 'http://[fe80::0123:4567:89ab:cdef]/'

    cookie = HTTP::Cookie.new(cookie_values(:domain => '[fe80::0123:4567:89ab:cdef]', :origin => url))
    @jar.add(cookie)

    assert_equal(1, @jar.cookies(url).length)
  end

  def test_cookies_dot
    url = URI 'http://www.host.example/'

    @jar.add(HTTP::Cookie.new(cookie_values(:domain => 'www.host.example', :origin => url)))

    url = URI 'http://wwwxhost.example/'
    assert_equal(0, @jar.cookies(url).length)
  end

  def test_clear
    url = URI 'http://rubyforge.org/'

    # Add one cookie with an expiration date in the future
    cookie = HTTP::Cookie.new(cookie_values(:origin => url))
    @jar.add(cookie)
    @jar.add(HTTP::Cookie.new(cookie_values(:name => 'Baz', :origin => url)))
    assert_equal(2, @jar.cookies(url).length)

    @jar.clear

    assert_equal(0, @jar.cookies(url).length)
  end

  def test_save_cookies_yaml
    url = URI 'http://rubyforge.org/'

    # Add one cookie with an expiration date in the future
    cookie = HTTP::Cookie.new(cookie_values(:origin => url))
    s_cookie = HTTP::Cookie.new(cookie_values(:name => 'Bar',
                                              :expires => nil,
                                              :session => true,
                                              :origin => url))

    @jar.add(cookie)
    @jar.add(s_cookie)
    @jar.add(HTTP::Cookie.new(cookie_values(:name => 'Baz', :for_domain => false, :origin => url)))

    assert_equal(3, @jar.cookies(url).length)

    in_tmpdir do
      value = @jar.save_as("cookies.yml")
      assert_same @jar, value

      jar = HTTP::CookieJar.new
      jar.load("cookies.yml")
      cookies = jar.cookies(url).sort_by { |cookie| cookie.name }
      assert_equal(2, cookies.length)
      assert_equal('Baz', cookies[0].name)
      assert_equal(false, cookies[0].for_domain)
      assert_equal('Foo', cookies[1].name)
      assert_equal(true,  cookies[1].for_domain)
    end

    assert_equal(3, @jar.cookies(url).length)
  end

  def test_save_session_cookies_yaml
    url = URI 'http://rubyforge.org/'

    # Add one cookie with an expiration date in the future
    cookie = HTTP::Cookie.new(cookie_values)
    s_cookie = HTTP::Cookie.new(cookie_values(:name => 'Bar',
                                              :expires => nil,
                                              :session => true))

    @jar.add(cookie)
    @jar.add(s_cookie)
    @jar.add(HTTP::Cookie.new(cookie_values(:name => 'Baz')))

    assert_equal(3, @jar.cookies(url).length)

    in_tmpdir do
      @jar.save_as("cookies.yml", :format => :yaml, :session => true)

      jar = HTTP::CookieJar.new
      jar.load("cookies.yml")
      assert_equal(3, jar.cookies(url).length)
    end

    assert_equal(3, @jar.cookies(url).length)
  end


  def test_save_cookies_cookiestxt
    url = URI 'http://rubyforge.org/foo/'

    # Add one cookie with an expiration date in the future
    cookie = HTTP::Cookie.new(cookie_values)
    s_cookie = HTTP::Cookie.new(cookie_values(:name => 'Bar',
                                              :expires => nil,
                                              :session => true))

    @jar.add(cookie)
    @jar.add(s_cookie)
    @jar.add(HTTP::Cookie.new(cookie_values(:name => 'Baz', :value => 'Foo#Baz', :path => '/foo/', :for_domain => false)))

    assert_equal(3, @jar.cookies(url).length)

    in_tmpdir do
      @jar.save_as("cookies.txt", :cookiestxt)

      jar = HTTP::CookieJar.new
      jar.load("cookies.txt", :cookiestxt) # HACK test the format
      cookies = jar.cookies(url)
      assert_equal(2, cookies.length)
      cookies.each { |cookie|
        case cookie.name
        when 'Foo'
          assert_equal 'Bar', cookie.value
          assert_equal 'rubyforge.org', cookie.domain
          assert_equal true, cookie.for_domain
          assert_equal '/', cookie.path
        when 'Baz'
          assert_equal 'Foo#Baz', cookie.value
          assert_equal 'rubyforge.org', cookie.domain
          assert_equal false, cookie.for_domain
          assert_equal '/foo/', cookie.path
        else
          raise
        end
      }
    end

    assert_equal(3, @jar.cookies(url).length)
  end

  def test_expire_cookies
    url = URI 'http://rubyforge.org/'

    # Add one cookie with an expiration date in the future
    cookie = HTTP::Cookie.new(cookie_values)
    @jar.add(cookie)
    assert_equal(1, @jar.cookies(url).length)

    # Add a second cookie
    @jar.add(HTTP::Cookie.new(cookie_values(:name => 'Baz')))
    assert_equal(2, @jar.cookies(url).length)

    # Make sure we can get the cookie from different paths
    assert_equal(2, @jar.cookies(URI('http://rubyforge.org/login')).length)

    # Expire the first cookie
    @jar.add(HTTP::Cookie.new(cookie_values(:expires => Time.now - (10 * 86400))))
    assert_equal(1, @jar.cookies(url).length)

    # Expire the second cookie
    @jar.add(HTTP::Cookie.new(cookie_values( :name => 'Baz', :expires => Time.now - (10 * 86400))))
    assert_equal(0, @jar.cookies(url).length)
  end

  def test_session_cookies
    values = cookie_values(:expires => nil)
    url = URI 'http://rubyforge.org/'

    # Add one cookie with an expiration date in the future
    cookie = HTTP::Cookie.new(values)
    @jar.add(cookie)
    assert_equal(1, @jar.cookies(url).length)

    # Add a second cookie
    @jar.add(HTTP::Cookie.new(values.merge(:name => 'Baz')))
    assert_equal(2, @jar.cookies(url).length)

    # Make sure we can get the cookie from different paths
    assert_equal(2, @jar.cookies(URI('http://rubyforge.org/login')).length)

    # Expire the first cookie
    @jar.add(HTTP::Cookie.new(values.merge(:expires => Time.now - (10 * 86400))))
    assert_equal(1, @jar.cookies(url).length)

    # Expire the second cookie
    @jar.add(HTTP::Cookie.new(values.merge(:name => 'Baz', :expires => Time.now - (10 * 86400))))
    assert_equal(0, @jar.cookies(url).length)

    # When given a URI with a blank path, CookieJar#cookies should return
    # cookies with the path '/':
    url = URI 'http://rubyforge.org'
    assert_equal '', url.path
    assert_equal(0, @jar.cookies(url).length)
    # Now add a cookie with the path set to '/':
    @jar.add(HTTP::Cookie.new(values.merge(:name => 'has_root_path', :path => '/')))
    assert_equal(1, @jar.cookies(url).length)
  end

  def test_paths
    url = URI 'http://rubyforge.org/login'
    values = cookie_values(:path => "/login", :expires => nil, :origin => url)

    # Add one cookie with an expiration date in the future
    cookie = HTTP::Cookie.new(values)
    @jar.add(cookie)
    assert_equal(1, @jar.cookies(url).length)

    # Add a second cookie
    @jar.add(HTTP::Cookie.new(values.merge( :name => 'Baz' )))
    assert_equal(2, @jar.cookies(url).length)

    # Make sure we don't get the cookie in a different path
    assert_equal(0, @jar.cookies(URI('http://rubyforge.org/hello')).length)
    assert_equal(0, @jar.cookies(URI('http://rubyforge.org/')).length)

    # Expire the first cookie
    @jar.add(HTTP::Cookie.new(values.merge( :expires => Time.now - (10 * 86400))))
    assert_equal(1, @jar.cookies(url).length)

    # Expire the second cookie
    @jar.add(HTTP::Cookie.new(values.merge( :name => 'Baz',
                                          :expires => Time.now - (10 * 86400))))
    assert_equal(0, @jar.cookies(url).length)
  end

  def test_save_and_read_cookiestxt
    url = URI 'http://rubyforge.org/'

    # Add one cookie with an expiration date in the future
    cookie = HTTP::Cookie.new(cookie_values)
    @jar.add(cookie)
    @jar.add(HTTP::Cookie.new(cookie_values(:name => 'Baz')))
    assert_equal(2, @jar.cookies(url).length)

    in_tmpdir do
      @jar.save_as("cookies.txt", :cookiestxt)
      @jar.clear

      @jar.load("cookies.txt", :cookiestxt)
    end

    assert_equal(2, @jar.cookies(url).length)
  end

  def test_save_and_read_cookiestxt_with_session_cookies
    url = URI 'http://rubyforge.org/'

    @jar.add(HTTP::Cookie.new(cookie_values(:expires => nil)))

    in_tmpdir do
      @jar.save_as("cookies.txt", :cookiestxt)
      @jar.clear

      @jar.load("cookies.txt", :cookiestxt)
    end

    assert_equal(1, @jar.cookies(url).length)
    assert_nil @jar.cookies(url).first.expires
  end

  def test_save_and_read_expired_cookies
    url = URI 'http://rubyforge.org/'

    @jar.jar['rubyforge.org'] = {}


    @jar.add HTTP::Cookie.new(cookie_values)

    # HACK no asertion
  end

  def test_ssl_cookies
    # thanks to michal "ocher" ochman for reporting the bug responsible for this test.
    values = cookie_values(:expires => nil)
    values_ssl = values.merge(:name => 'Baz', :domain => "#{values[:domain]}:443")
    url = URI 'https://rubyforge.org/login'

    cookie = HTTP::Cookie.new(values)
    @jar.add(cookie)
    assert_equal(1, @jar.cookies(url).length, "did not handle SSL cookie")

    cookie = HTTP::Cookie.new(values_ssl)
    @jar.add(cookie)
    assert_equal(2, @jar.cookies(url).length, "did not handle SSL cookie with :443")
  end

  def test_secure_cookie
    nurl = URI 'http://rubyforge.org/login'
    surl = URI 'https://rubyforge.org/login'

    nncookie = HTTP::Cookie.new(cookie_values(:name => 'Foo1', :origin => nurl))
    sncookie = HTTP::Cookie.new(cookie_values(:name => 'Foo1', :origin => surl))
    nscookie = HTTP::Cookie.new(cookie_values(:name => 'Foo2', :secure => true, :origin => nurl))
    sscookie = HTTP::Cookie.new(cookie_values(:name => 'Foo2', :secure => true, :origin => surl))

    @jar.add(nncookie)
    @jar.add(sncookie)
    @jar.add(nscookie)
    @jar.add(sscookie)

    assert_equal('Foo1',      @jar.cookies(nurl).map { |c| c.name }.sort.join(' ') )
    assert_equal('Foo1 Foo2', @jar.cookies(surl).map { |c| c.name }.sort.join(' ') )
  end
end
