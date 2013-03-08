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

    # Initialize a cookie jar
    jar = HTTP::CookieJar.new

    # Load from a file
    jar.load(filename) if File.exist?(filename)

    # Store received cookies
    HTTP::Cookie.parse(set_cookie_header_value, :origin => uri) { |cookie|
      jar << cookie
    }

    # Extract cookies to send
    cookie_value_to_send = jar.cookies(uri).join(', ')

    # Save to a file
    jar.save_as(filename)

## To-Do list

- Print kind error messages to make migration from Mechanize::Cookie easier

- Make serializers pluggable/autoloadable and prepare a binary friendly API

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
