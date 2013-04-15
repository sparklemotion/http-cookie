require 'rubygems'
require 'test-unit'
require 'uri'
require 'http/cookie'

module Enumerable
  def combine
    masks = inject([[], 1]){|(ar, m), e| [ar << m, m << 1 ] }[0]
    all = masks.inject(0){ |al, m| al|m }

    result = []
    for i in 1..all do
      tmp = []
      each_with_index do |e, idx|
        tmp << e unless (masks[idx] & i) == 0
      end
      result << tmp
    end
    result
  end
end

def test_file(filename)
  File.expand_path(filename, File.dirname(__FILE__))
end
