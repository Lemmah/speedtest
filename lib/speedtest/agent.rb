require "socket"

module Speedtest
  class Agent
    MAX_DURATION_MS = 60_000

    def initialize(bind_address, port)
      @bind_address = bind_address
      @port = port
    end

    def run
      server = TCPServer.new(@bind_address, @port)
      running = true
      Signal.trap("INT") do
        running = false
      end
      Signal.trap("TERM") do
        running = false
      end

      puts "speedtest-agent #{VERSION} listening on #{@bind_address}:#{@port}"
      while running
        begin
          ready = IO.select([server], nil, nil, 0.5)
          next if ready.nil?
          socket = server.accept
          Thread.new(socket) { |connection| handle(connection) }
        rescue IOError, SystemCallError
          raise if running
        end
      end
    ensure
      server.close if !server.nil? && !server.closed?
    end

    private

    def handle(socket)
      hello = Protocol.parse(Protocol.read_line(socket))
      unless hello.name == "HELLO" && hello.arguments.length == 1
        Protocol.write_line(socket, "ERROR handshake expected-hello")
        return
      end
      unless hello.arguments[0] == PROTOCOL_VERSION.to_s
        Protocol.write_line(socket, "ERROR version supported-#{PROTOCOL_VERSION}")
        return
      end
      Protocol.write_line(socket, "OK #{PROTOCOL_VERSION}")

      loop do
        command = Protocol.parse(Protocol.read_line(socket))
        case command.name
        when "PING"
          if command.arguments.empty?
            Protocol.write_line(socket, "PONG")
          else
            Protocol.write_line(socket, "ERROR arguments ping-takes-none")
          end
        when "DOWNLOAD"
          duration = duration_seconds(command)
          download(socket, duration)
          return
        when "UPLOAD"
          duration = duration_seconds(command)
          upload(socket, duration)
          return
        when "QUIT"
          Protocol.write_line(socket, "BYE")
          return
        else
          Protocol.write_line(socket, "ERROR command unknown-command")
        end
      end
    rescue ProtocolError => error
      begin
        Protocol.write_line(socket, "ERROR protocol #{error.message}") unless socket.closed?
      rescue
      end
    rescue EOFError, IOError, SystemCallError
    ensure
      socket.close unless socket.closed?
    end

    def duration_seconds(command)
      unless command.arguments.length == 1
        raise ProtocolError, "duration command needs one argument"
      end
      Protocol.positive_integer(command.arguments[0], "duration", MAX_DURATION_MS).to_f / 1000.0
    end

    def await_go(socket)
      Protocol.write_line(socket, "READY")
      command = Protocol.parse(Protocol.read_line(socket))
      unless command.name == "GO" && command.arguments.empty?
        raise ProtocolError, "expected GO"
      end
    end

    def download(socket, duration)
      await_go(socket)
      buffer = "d" * Protocol::PAYLOAD_BYTES
      deadline = Clock.now + duration
      while Clock.now < deadline
        Protocol.write_all(socket, buffer)
      end
    end

    def upload(socket, duration)
      await_go(socket)
      bytes = 0
      loop do
        command = Protocol.parse(Protocol.read_line(socket))
        break if command.name == "DONE" && command.arguments.empty?
        unless command.name == "CHUNK" && command.arguments.length == 1
          raise ProtocolError, "expected CHUNK or DONE"
        end
        size = Protocol.positive_integer(command.arguments[0], "chunk size", Protocol::PAYLOAD_BYTES)
        remaining = size
        while remaining > 0
          chunk = socket.read(remaining)
          raise ProtocolError, "agent disconnect during upload chunk" if chunk.nil? || chunk.empty?
          remaining -= chunk.bytesize
          bytes += chunk.bytesize
        end
      end
      Protocol.write_line(socket, "RESULT #{bytes}")
    end
  end
end
