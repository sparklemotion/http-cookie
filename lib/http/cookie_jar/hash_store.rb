require 'http/cookie_jar'

class Array
  def sort_by!(&block)
    replace(sort_by(&block))
  end unless method_defined?(:sort_by!)
end

class HTTP::CookieJar
  class HashStore < AbstractStore
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
      end

      self
    end

    def each(uri = nil)
      if uri
        uri = URI(uri)
        thost = DomainName.new(uri.host)
        tpath = HTTP::Cookie.normalize_path(uri.path)
        @jar.each { |domain, paths|
          next unless thost.cookie_domain?(domain)
          paths.each { |path, hash|
            next unless tpath.start_with?(path)
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
    end

    def clear
      @jar.clear
      self
    end

    def empty?
      @jar.empty?
    end
  end
end
