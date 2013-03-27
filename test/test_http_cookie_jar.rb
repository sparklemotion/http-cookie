require File.expand_path('helper', File.dirname(__FILE__))
require 'tmpdir'

class TestHTTPCookieJar < Test::Unit::TestCase
  def setup
    @jar = HTTP::CookieJar.new
  end

  def cookie_values(options = {})
    {
      :name     => 'Foo',
      :value    => 'Bar',
      :path     => '/',
      :expires  => Time.at(Time.now.to_i + 10 * 86400), # to_i is important here
      :for_domain => true,
      :domain   => 'rubyforge.org',
      :origin   => 'http://rubyforge.org/'
   }.merge(options)
  end

  def test_empty?
    assert_equal true, @jar.empty?
    cookie = HTTP::Cookie.new(cookie_values)
    @jar.add(cookie)
    assert_equal false, @jar.empty?
    assert_equal false, @jar.empty?('http://rubyforge.org/')
    assert_equal true, @jar.empty?('http://example.local/')
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

  def test_cookies_no_host
    url = URI 'file:///path/'

    assert_raises(ArgumentError) {
      @jar.add(HTTP::Cookie.new(cookie_values(:origin => url)))
    }

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

    Dir.mktmpdir do |dir|
      value = @jar.save(File.join(dir, "cookies.yml"))
      assert_same @jar, value

      jar = HTTP::CookieJar.new
      jar.load(File.join(dir, "cookies.yml"))
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

    Dir.mktmpdir do |dir|
      @jar.save(File.join(dir, "cookies.yml"), :format => :yaml, :session => true)

      jar = HTTP::CookieJar.new
      jar.load(File.join(dir, "cookies.yml"))
      assert_equal(3, jar.cookies(url).length)
    end

    assert_equal(3, @jar.cookies(url).length)
  end


  def test_save_and_read_cookiestxt
    url = URI 'http://rubyforge.org/foo/'

    # Add one cookie with an expiration date in the future
    cookie = HTTP::Cookie.new(cookie_values)
    expires = cookie.expires
    s_cookie = HTTP::Cookie.new(cookie_values(:name => 'Bar',
                                              :expires => nil,
                                              :session => true))
    cookie2 = HTTP::Cookie.new(cookie_values(:name => 'Baz',
                                             :value => 'Foo#Baz',
                                             :path => '/foo/',
                                             :for_domain => false))
    h_cookie = HTTP::Cookie.new(cookie_values(:name => 'Quux',
                                              :value => 'Foo#Quux',
                                              :httponly => true))
    ma_cookie = HTTP::Cookie.new(cookie_values(:name => 'Maxage',
                                               :value => 'Foo#Maxage',
                                               :max_age => 15000))
    @jar.add(cookie)
    @jar.add(s_cookie)
    @jar.add(cookie2)
    @jar.add(h_cookie)
    @jar.add(ma_cookie)

    assert_equal(5, @jar.cookies(url).length)

    Dir.mktmpdir do |dir|
      filename = File.join(dir, "cookies.txt")
      @jar.save(filename, :cookiestxt)

      content = File.read(filename)

      assert_match(/^\.rubyforge\.org\t.*\tFoo\t/, content)
      assert_match(/^rubyforge\.org\t.*\tBaz\t/, content)
      assert_match(/^#HttpOnly_\.rubyforge\.org\t/, content)

      jar = HTTP::CookieJar.new
      jar.load(filename, :cookiestxt) # HACK test the format
      cookies = jar.cookies(url)
      assert_equal(4, cookies.length)
      cookies.each { |cookie|
        case cookie.name
        when 'Foo'
          assert_equal 'Bar', cookie.value
          assert_equal expires, cookie.expires
          assert_equal 'rubyforge.org', cookie.domain
          assert_equal true, cookie.for_domain
          assert_equal '/', cookie.path
          assert_equal false, cookie.httponly?
        when 'Baz'
          assert_equal 'Foo#Baz', cookie.value
          assert_equal 'rubyforge.org', cookie.domain
          assert_equal false, cookie.for_domain
          assert_equal '/foo/', cookie.path
          assert_equal false, cookie.httponly?
        when 'Quux'
          assert_equal 'Foo#Quux', cookie.value
          assert_equal expires, cookie.expires
          assert_equal 'rubyforge.org', cookie.domain
          assert_equal true, cookie.for_domain
          assert_equal '/', cookie.path
          assert_equal true, cookie.httponly?
        when 'Maxage'
          assert_equal 'Foo#Maxage', cookie.value
          assert_equal nil, cookie.max_age
          assert_in_delta ma_cookie.expires, cookie.expires, 1
        else
          raise
        end
      }
    end

    assert_equal(5, @jar.cookies(url).length)
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

  def h_test_max_cookies(jar, slimit)
    limit_per_domain = HTTP::Cookie::MAX_COOKIES_PER_DOMAIN
    uri = URI('http://www.example.org/')
    date = Time.at(Time.now.to_i + 86400)
    (1..(limit_per_domain + 1)).each { |i|
      jar << HTTP::Cookie.new(cookie_values(
          :name => 'Foo%d' % i,
          :value => 'Bar%d' % i,
          :domain => uri.host,
          :for_domain => true,
          :path => '/dir%d/' % (i / 2),
          :origin => uri
          )).tap { |cookie|
        cookie.created_at = i == 42 ? date - i : date
      }
    }
    assert_equal limit_per_domain + 1, jar.to_a.size
    jar.cleanup
    count = jar.to_a.size
    assert_equal limit_per_domain, count
    assert_equal [*1..41] + [*43..(limit_per_domain + 1)], jar.map { |cookie|
      cookie.name[/(\d+)$/].to_i
    }.sort

    hlimit = HTTP::Cookie::MAX_COOKIES_TOTAL

    n = hlimit / limit_per_domain * 2

    (1..n).each { |i|
      (1..(limit_per_domain + 1)).each { |j|
        uri = URI('http://www%d.example.jp/' % i)
        jar << HTTP::Cookie.new(cookie_values(
            :name => 'Baz%d' % j,
            :value => 'www%d.example.jp' % j,
            :domain => uri.host,
            :for_domain => true,
            :path => '/dir%d/' % (i / 2),
            :origin => uri
            )).tap { |cookie|
          cookie.created_at = i == j ? date - i : date
        }
        count += 1
      }
    }

    assert_equal true, count > slimit
    assert_equal true, jar.to_a.size <= slimit
    jar.cleanup
    assert_equal hlimit, jar.to_a.size
    assert_equal false, jar.any? { |cookie|
      cookie.domain == cookie.value
    }
  end

  def test_max_cookies_hashstore
    gc_threshold = 150
    h_test_max_cookies(
      HTTP::CookieJar.new(
        :store => :hash,
        :gc_threshold => gc_threshold),
      HTTP::Cookie::MAX_COOKIES_TOTAL + gc_threshold)
  end

  def test_max_cookies_mozillastore
    gc_threshold = 150
    h_test_max_cookies(
      HTTP::CookieJar.new(
        :store => :mozilla,
        :gc_threshold => gc_threshold,
        :filename => ":memory:"),
      HTTP::Cookie::MAX_COOKIES_TOTAL + gc_threshold)
    #Dir.mktmpdir { |dir|
    #  h_test_max_cookies(
    #    HTTP::CookieJar.new(
    #      :store => :mozilla,
    #      :gc_threshold => gc_threshold,
    #      :filename => File.join(dir, "cookies.sqlite")),
    #    HTTP::Cookie::MAX_COOKIES_TOTAL + gc_threshold)
    #}
  rescue IndexError
    STDERR.puts 'sqlite3 missing?'
  end
end
