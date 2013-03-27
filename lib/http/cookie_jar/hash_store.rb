require 'http/cookie_jar'

# :stopdoc:
class Array
  def sort_by!(&block)
    replace(sort_by(&block))
  end unless method_defined?(:sort_by!)
end
# :startdoc:

class HTTP::CookieJar
  # A store class that uses a hash of hashes.
  class HashStore < AbstractStore
    def default_options
      {
        :gc_threshold => HTTP::Cookie::MAX_COOKIES_TOTAL / 20
      }
    end

    def initialize(options = nil)
      super

      @jar = {}
      # {
      #   hostname => {
      #     path => {
      #       name => cookie,
      #       ...
      #     },
      #     ...
      #   },
      #   ...
      # }

      @gc_index = 0
    end

    def initialize_copy(other)
      @jar = Marshal.load(Marshal.dump(other.instance_variable_get(:@jar)))
    end

    def add(cookie)
      path_cookies = ((@jar[cookie.domain_name.hostname] ||= {})[cookie.path] ||= {})
      path_cookies[cookie.name] = cookie
      cleanup if (@gc_index += 1) >= @gc_threshold
      self
    end

    def delete(cookie)
      path_cookies = ((@jar[cookie.domain_name.hostname] ||= {})[cookie.path] ||= {})
      path_cookies.delete(cookie.name)
      self
    end
    private :delete

    def each(uri = nil)
      now = Time.now
      if uri
        thost = DomainName.new(uri.host)
        tpath = uri.path
        @jar.each { |domain, paths|
          next unless thost.cookie_domain?(domain)
          paths.each { |path, hash|
            next unless HTTP::Cookie.path_match?(path, tpath)
            hash.delete_if { |name, cookie|
              if cookie.expired?(now)
                true
              else
                if cookie.valid_for_uri?(uri)
                  cookie.accessed_at = now
                  yield cookie
                end
                false
              end
            }
          }
        }
      else
        @jar.each { |domain, paths|
          paths.each { |path, hash|
            hash.delete_if { |name, cookie|
              if cookie.expired?(now)
                true
              else
                yield cookie
                false
              end
            }
          }
        }
      end
      self
    end

    def clear
      @jar.clear
      self
    end

    def empty?
      @jar.empty?
    end

    def cleanup(session = false)
      now = Time.now
      all_cookies = []
      @jar.each { |domain, paths|
        domain_cookies = []

        paths.each { |path, hash|
          hash.delete_if { |name, cookie|
            if cookie.expired?(now) || (session && cookie.session?)
              true
            else
              domain_cookies << cookie
              false
            end
          }
        }

        if (debt = domain_cookies.size - HTTP::Cookie::MAX_COOKIES_PER_DOMAIN) > 0
          domain_cookies.sort_by!(&:created_at)
          domain_cookies.slice!(0, debt).each { |cookie|
            delete(cookie)
          }
        end

        all_cookies.concat(domain_cookies)
      }

      if (debt = all_cookies.size - HTTP::Cookie::MAX_COOKIES_TOTAL) > 0
        all_cookies.sort_by!(&:created_at)
        all_cookies.slice!(0, debt).each { |cookie|
          delete(cookie)
        }
      end

      @jar.delete_if { |domain, paths|
        paths.delete_if { |path, hash|
          hash.empty?
        }
        paths.empty?
      }

      @gc_index = 0
    end
  end
end
