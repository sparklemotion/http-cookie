class Array
  def select!
    i = 0
    each_with_index { |x, j|
      yield x or next
      self[i] = x if i != j
      i += 1
    }
    return nil if i == size
    self[i..-1] = []
    self
  end unless method_defined?(:select!)
end

# In Ruby < 1.9.3 URI() does not accept a URI object.
if RUBY_VERSION < "1.9.3"
  require 'uri'

  begin
    URI(URI(''))
  rescue
    def URI(url) # :nodoc:
      case url
      when URI
        url
      when String
        URI.parse(url)
      else
        raise ArgumentError, 'bad argument (expected URI object or URI string)'
      end
    end
  end
end
