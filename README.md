# HTTP::Cookie

HTTP::Cookie is a ruby library to handle HTTP cookies in a way both
compliant with RFCs and compatible with today's major browsers.

It was originally a part of the Mechanize library, separated as an
independent library in the hope of serving as a common component that
is reusable from any HTTP related piece of software.

## Installation

Add this line to your application's Gemfile:

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


## To-Do list

- Print kind error messages to make migration from Mechanize::Cookie easier

- Make serializers pluggable/autoloadable and prepare a binary friendly API

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
