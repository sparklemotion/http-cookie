# HTTP::Cookie

`HTTP::Cookie` is a ruby library to handle HTTP cookies in a way both
compliant with RFCs and compatible with today's major browsers.

It was originally a part of the
[Mechanize](https://github.com/sparklemotion/mechanize) library,
separated as an independent library in the hope of serving as a common
component that is reusable from any HTTP related piece of software.

## Installation

Add this line to your application's `Gemfile`:

    gem 'http-cookie'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install http-cookie

## Usage

    ########################
    # Client side example
    ########################

    # Initialize a cookie jar
    jar = HTTP::CookieJar.new

    # Load from a file
    jar.load(filename) if File.exist?(filename)

    # Store received cookies
    HTTP::Cookie.parse(set_cookie_header_value, origin: uri) { |cookie|
      jar << cookie
    }

    # Get the value for the Cookie field of a request header
    cookie_header_value = jar.cookies(uri).join(', ')

    # Save to a file
    jar.save(filename)


    ########################
    # Server side example
    ########################

    # Generate a cookie
    cookies = HTTP::Cookie.new("uid", "a12345", domain: 'example.org',
                                                for_domain: true,
                                                path: '/',
                                                max_age: 7*86400)

    # Get the value for the Set-Cookie field of a response header
    set_cookie_header_value = cookies.set_cookie_value(my_url)


## Incompatibilities with `Mechanize::Cookie`/`CookieJar`

There are several incompatibilities between
`Mechanize::Cookie`/`CookieJar` and `HTTP::Cookie`/`CookieJar`.  Below
is how to rewrite existing code written for `Mechanize::Cookie` with
equivalent using `HTTP::Cookie`:

- `Mechanize::Cookie.parse`

        # before
        cookies1 = Mechanize::Cookie.parse(uri, set_cookie1)
        cookies2 = Mechanize::Cookie.parse(uri, set_cookie2, log)

        # after
        cookies1 = HTTP::Cookie.parse(set_cookie1, uri_or_url)
        cookies2 = HTTP::Cookie.parse(set_cookie2, uri_or_url, :logger => log)

- `Mechanize::Cookie#version`, `#version=`

    There is no longer a sense of version in HTTP cookie.  The only
    version number that has ever been defined was zero, and there will
    be no other version since the version attribute has been removed
    in RFC 6265.

- `Mechanize::Cookie#comment`, `#comment=`

    Ditto.  The comment attribute has been removed in RFC 6265.

- `Mechanize::Cookie#set_domain`

        # before
        cookie.set_domain(domain)

        # after
        cookie.domain = domain

- `Mechanize::CookieJar#add`, `#add!`

        # before
        jar.add!(cookie1)
        jar.add(uri, cookie2)

        # after
        jar.add(cookie1)
        cookie2.origin = uri; jar.add(cookie2)  # or specify origin in parse() or new()

- `Mechanize::CookieJar#clear!`

        # before
        jar.clear!

        # after
        jar.clear

- `Mechanize::CookieJar#save_as`

        # before
        jar.save_as(file)

        # after
        jar.save(file)

- `Mechanize::CookieJar#jar`

    There is no direct access to the internal hash in
    `HTTP::CookieJar` since it has introduced an abstract store layer.
    If you want to tweak the internals of the hash store, try creating
    a new store class referring to the default store class
    `HTTP::CookieJar::HashStore`.

    If you desperately need it you can access it by
    `jar.store.instance_variable_get(:@jar)`, but there is no
    guarantee that it will remain available in the future.


`HTTP::Cookie`/`CookieJar` raise runtime errors to help migration, so
after replacing the class names, try running your test code once to
find out how to fix your code base.

### File formats

The YAML serialization format has changed, and `HTTP::CookieJar#load`
cannot import what is written in a YAML file saved by
`Mechanize::CookieJar#save_as`.  `HTTP::CookieJar#load` will not raise
an exception if an incompatible YAML file is given, but the content is
silently ignored.

Note that there is (obviously) no forward compatibillity with this.
Trying to load a YAML file saved by `HTTP::CookieJar` with
`Mechanize::CookieJar` will fail in runtime error.

On the other hand, there has been (and will ever be) no change in the
cookies.txt format, so use it instead if compatibility is significant.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
