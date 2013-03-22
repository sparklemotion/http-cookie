require 'http/cookie_jar'

# :stopdoc:
class Array
  def sort_by!(&block)
    replace(sort_by(&block))
  end unless method_defined?(:sort_by!)
end
# :startdoc:

class HTTP::CookieJar
  class HashStore < AbstractStore
    GC_THRESHOLD = HTTP::Cookie::MAX_COOKIES_TOTAL / 20

    def default_options
      {}
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

      if cookie.expired?
        path_cookies.delete(cookie.name)
      else
        path_cookies[cookie.name] = cookie
        cleanup if (@gc_index += 1) >= GC_THRESHOLD
      end

      self
    end

    def each(uri = nil)
      if uri
        thost = DomainName.new(uri.host)
        tpath = uri.path
        @jar.each { |domain, paths|
          next unless thost.cookie_domain?(domain)
          paths.each { |path, hash|
            next unless HTTP::Cookie.path_match?(path, tpath)
            hash.delete_if { |name, cookie|
              if cookie.expired?
                true
              else
                cookie.accessed_at = Time.now
                yield cookie
                false
              end
            }
          }
        }
      else
        @jar.each { |domain, paths|
          paths.each { |path, hash|
            hash.delete_if { |name, cookie|
              if cookie.expired?
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
      all_cookies = []

      @jar.each { |domain, paths|
        domain_cookies = []

        paths.each { |path, hash|
          hash.delete_if { |name, cookie|
            if cookie.expired? || (session && cookie.session?)
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
            add(cookie.expire!)
          }
        end

        all_cookies.concat(domain_cookies)
      }

      if (debt = all_cookies.size - HTTP::Cookie::MAX_COOKIES_TOTAL) > 0
        all_cookies.sort_by!(&:created_at)
        all_cookies.slice!(0, debt).each { |cookie|
          add(cookie.expire!)
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
