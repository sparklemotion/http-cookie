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

module Test::Unit::Assertions
  def assert_raises_with_message(exc, re, message = nil, &block)
    e = nil
    begin
      block.call
    rescue Exception => e
    end
    assert_instance_of(exc, e, message)
    assert_match(re, e.message, message)
  end
end
