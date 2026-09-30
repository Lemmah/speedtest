require "socket"

module Speedtest
  class Client
    def initialize(endpoint, duration, streams, ping_samples, connect_timeout)
      @endpoint = endpoint
      @duration = duration
      @streams = streams
      @ping_samples = ping_samples
      @connect_timeout = connect_timeout
    end

    def run
      test_started = Clock.now
      control = connect
      Protocol.handshake_client(control)

      idle = measure_idle(control)
      download = run_download(control)
      upload = run_upload(control)

      Protocol.write_line(control, "QUIT")
      Protocol.expect(control, "BYE")
      control.close

      TestResult.new(idle, download[1], upload[1], download[0], upload[0], Clock.now - test_started)
    ensure
      control.close if !control.nil? && !control.closed?
    end

    private

    def connect
      thread = Thread.new { TCPSocket.new(@endpoint.host, @endpoint.port) }
      if thread.join(@connect_timeout).nil?
        thread.kill
        raise Error, "connection to #{@endpoint.address} timed out after #{@connect_timeout} seconds"
      end
      thread.value
    end

    def ping(socket)
      started = Clock.now
      Protocol.write_line(socket, "PING")
      Protocol.expect(socket, "PONG")
      (Clock.now - started) * 1000.0
    end

    def measure_idle(control)
      samples = []
      @ping_samples.times do |index|
        samples << ping(control)
        sleep(0.1) if index + 1 < @ping_samples
      end
      samples
    end

    def prepare_streams(command)
      sockets = []
      @streams.times do
        socket = connect
        Protocol.handshake_client(socket)
        Protocol.write_line(socket, "#{command} #{(@duration * 1000.0).round}")
        Protocol.expect(socket, "READY")
        sockets << socket
      end
      sockets
    rescue
      sockets.each { |socket| socket.close unless socket.closed? }
      raise
    end

    def loaded_pings(control, start_at)
      Clock.sleep_until(start_at)
      deadline = start_at + @duration
      samples = []
      while Clock.now < deadline
        samples << ping(control)
        sleep(0.1) if Clock.now < deadline
      end
      samples
    end

    def run_download(control)
      sockets = prepare_streams("DOWNLOAD")
      start_at = Clock.now + 0.15
      latency_thread = Thread.new { loaded_pings(control, start_at) }
      workers = sockets.map do |socket|
        Thread.new(socket) do |stream|
          Clock.sleep_until(start_at)
          Protocol.write_line(stream, "GO")
          started = Clock.now
          bytes = 0
          begin
            loop do
              chunk = stream.read(Protocol::PAYLOAD_BYTES)
              break if chunk.nil? || chunk.empty?
              bytes += chunk.bytesize
            end
          ensure
            stream.close unless stream.closed?
          end
          TransferResult.new(bytes, Clock.now - started)
        end
      end

      bytes = 0
      elapsed = 0.0
      workers.each do |worker|
        transfer = worker.value
        bytes += transfer.bytes
        elapsed = transfer.elapsed if transfer.elapsed > elapsed
      end
      [Statistics.mbps(bytes, elapsed), latency_thread.value]
    end

    def run_upload(control)
      sockets = prepare_streams("UPLOAD")
      start_at = Clock.now + 0.15
      latency_thread = Thread.new { loaded_pings(control, start_at) }
      workers = sockets.map do |socket|
        Thread.new(socket) do |stream|
          Clock.sleep_until(start_at)
          Protocol.write_line(stream, "GO")
          buffer = "u" * Protocol::PAYLOAD_BYTES
          bytes = 0
          started = Clock.now
          deadline = started + @duration
          while Clock.now < deadline
            Protocol.write_line(stream, "CHUNK #{buffer.bytesize}")
            bytes += Protocol.write_all(stream, buffer)
          end
          elapsed = Clock.now - started
          Protocol.write_line(stream, "DONE")
          result = Protocol.parse(Protocol.read_line(stream))
          unless result.name == "RESULT" && result.arguments.length == 1
            raise ProtocolError, "invalid upload result"
          end
          stream.close
          TransferResult.new(bytes, elapsed)
        ensure
          stream.close if !stream.nil? && !stream.closed?
        end
      end

      bytes = 0
      elapsed = 0.0
      workers.each do |worker|
        transfer = worker.value
        bytes += transfer.bytes
        elapsed = transfer.elapsed if transfer.elapsed > elapsed
      end
      [Statistics.mbps(bytes, elapsed), latency_thread.value]
    end
  end
end
