#!/usr/bin/env ruby

require_relative "../lib/speedtest"

class TestFailure < StandardError
end

def assert(description, value)
  raise TestFailure, description unless value
  puts "ok - #{description}"
end

def assert_close(description, expected, actual, tolerance)
  assert(description, (expected - actual).abs <= tolerance)
end

assert_close("throughput uses decimal megabits", 8.0, Speedtest::Statistics.mbps(1_000_000, 1.0), 0.0001)
assert_close("median odd", 3.0, Speedtest::Statistics.median([5.0, 1.0, 3.0]), 0.0001)
assert_close("median even", 2.5, Speedtest::Statistics.median([4.0, 1.0, 3.0, 2.0]), 0.0001)
assert_close("p95 nearest rank", 10.0, Speedtest::Statistics.percentile((1..10).map(&:to_f), 0.95), 0.0001)
assert_close("jitter is mean consecutive absolute difference", 3.0, Speedtest::Statistics.jitter([10.0, 14.0, 12.0]), 0.0001)

command = Speedtest::Protocol.parse("DOWNLOAD 1000")
assert("protocol parses command", command.name == "DOWNLOAD")
assert("protocol parses arguments", command.arguments == ["1000"])

class PartialWriter
  attr_reader :data

  def initialize
    @data = String.new
  end

  def write(chunk)
    count = [3, chunk.bytesize].min
    @data << chunk.byteslice(0, count)
    count
  end
end

writer = PartialWriter.new
Speedtest::Protocol.write_all(writer, "partial-write")
assert("protocol retries partial writes", writer.data == "partial-write")

servers = Speedtest::Config.parse(<<~CONFIG)
  # locations
  home 192.168.1.20 9876
  fra1 fra1.example.com 9000 # inline comment
CONFIG
assert("config parses entries", servers.length == 2)
assert("config parses host", servers["fra1"].host == "fra1.example.com")
assert("config parses port", servers["home"].port == 9876)

direct = Speedtest::Config.direct_endpoint("203.0.113.10:4567")
assert("direct address host", direct.host == "203.0.113.10")
assert("direct address port", direct.port == 4567)

ipv6 = Speedtest::Config.direct_endpoint("[::1]:9876")
assert("bracketed IPv6", ipv6.host == "::1" && ipv6.port == 9876)

puts "all tests passed"
