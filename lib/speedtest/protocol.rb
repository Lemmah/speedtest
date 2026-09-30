require "socket"

module Speedtest
  module Protocol
    MAX_LINE_BYTES = 1024
    PAYLOAD_BYTES = 65_536

    class Command
      attr_reader :name, :arguments

      def initialize(name, arguments)
        @name = name
        @arguments = arguments
      end
    end

    def self.read_line(io)
      line = io.gets
      raise ProtocolError, "agent disconnected" if line.nil?
      raise ProtocolError, "protocol line exceeds #{MAX_LINE_BYTES} bytes" if line.bytesize > MAX_LINE_BYTES
      raise ProtocolError, "protocol line is not newline terminated" unless line.end_with?("\n")

      line.chomp
    end

    # Blocking IO#write normally consumes the entire string. Keep the loop so
    # short writes are still handled correctly by any compatible IO object.
    def self.write_all(io, data)
      offset = 0
      while offset < data.bytesize
        written = io.write(data.byteslice(offset, data.bytesize - offset))
        raise ProtocolError, "socket write made no progress" if written.nil? || written <= 0
        offset += written
      end
      offset
    end

    def self.write_line(io, line)
      write_all(io, line + "\n")
    end

    def self.parse(line)
      fields = line.split(" ")
      raise ProtocolError, "empty command" if fields.empty? || fields[0].empty?

      Command.new(fields[0], fields[1..] || [])
    end

    def self.positive_integer(text, label, maximum)
      value = Integer(text, 10)
      raise ProtocolError, "#{label} must be between 1 and #{maximum}" if value < 1 || value > maximum

      value
    rescue ArgumentError
      raise ProtocolError, "invalid #{label}"
    end

    def self.handshake_client(io)
      write_line(io, "HELLO #{PROTOCOL_VERSION}")
      response = parse(read_line(io))
      unless response.name == "OK" && response.arguments.length == 1 && response.arguments[0] == PROTOCOL_VERSION.to_s
        raise ProtocolError, "protocol mismatch: expected OK #{PROTOCOL_VERSION}"
      end
      true
    end

    def self.expect(io, expected)
      response = read_line(io)
      if response.start_with?("ERROR ")
        raise ProtocolError, response
      end
      raise ProtocolError, "expected #{expected}, received #{response}" unless response == expected

      true
    end
  end
end
