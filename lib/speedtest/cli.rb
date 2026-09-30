module Speedtest
  class CLI
    HELP = <<~TEXT
      Usage:
        speedtest --help
        speedtest --version
        speedtest servers [--config PATH]
        speedtest test <server|host:port> [options]

      Test options:
        --duration SECONDS   Download and upload duration (default: 10)
        --streams COUNT      Concurrent throughput streams (default: 4)
        --samples COUNT      Idle latency samples (default: 10)
        --timeout SECONDS    TCP connect timeout (default: 5)
        --config PATH        Server registry path
    TEXT

    def self.run(arguments)
      new(arguments).run
    rescue Error => error
      warn "speedtest: #{error.message}"
      1
    rescue SocketError, SystemCallError => error
      warn "speedtest: connection failed: #{error.message}"
      1
    rescue IOError, EOFError => error
      warn "speedtest: connection closed: #{error.message}"
      1
    end

    def initialize(arguments)
      @arguments = arguments
      @duration = 10.0
      @streams = 4
      @samples = 10
      @timeout = 5.0
      @config_path = nil
    end

    def run
      if @arguments.empty? || @arguments[0] == "--help" || @arguments[0] == "-h"
        puts HELP
        return 0
      end
      if @arguments[0] == "--version"
        puts "speedtest #{VERSION}"
        return 0
      end

      command = @arguments[0]
      case command
      when "servers"
        parse_options(1)
        show_servers
      when "test"
        raise ConfigError, "test requires a server name or host:port" if @arguments.length < 2
        target = @arguments[1]
        parse_options(2)
        perform_test(target)
      else
        raise ConfigError, "unknown command '#{command}'; try --help"
      end
      0
    end

    private

    def parse_options(start_index)
      index = start_index
      while index < @arguments.length
        option = @arguments[index]
        value = @arguments[index + 1]
        raise ConfigError, "missing value for #{option}" if value.nil?
        case option
        when "--duration"
          begin
            @duration = Float(value)
          rescue ArgumentError
            raise ConfigError, "invalid duration '#{value}'"
          end
          raise ConfigError, "duration must be between 0.1 and 60 seconds" if @duration < 0.1 || @duration > 60.0
        when "--streams"
          @streams = parse_integer(value, "streams", 1, 16)
        when "--samples"
          @samples = parse_integer(value, "samples", 2, 100)
        when "--timeout"
          begin
            @timeout = Float(value)
          rescue ArgumentError
            raise ConfigError, "invalid timeout '#{value}'"
          end
          raise ConfigError, "timeout must be between 0.1 and 60 seconds" if @timeout < 0.1 || @timeout > 60.0
        when "--config"
          @config_path = value
        else
          raise ConfigError, "unknown option '#{option}'"
        end
        index += 2
      end
    end

    def parse_integer(value, label, minimum, maximum)
      begin
        number = Integer(value, 10)
      rescue ArgumentError
        raise ConfigError, "invalid #{label} '#{value}'"
      end
      if number < minimum || number > maximum
        raise ConfigError, "#{label} must be between #{minimum} and #{maximum}"
      end
      number
    end

    def registry
      Config.load(@config_path || Config.default_path)
    end

    def show_servers
      puts "Servers"
      registry.keys.sort.each do |name|
        endpoint = registry[name]
        puts "  %-20s %s" % [name, endpoint.address]
      end
    end

    def perform_test(target)
      endpoint = Config.resolve(target, registry)
      puts "Server:  #{endpoint.name}"
      puts "Address: #{endpoint.address}"
      puts "Streams: #{@streams}"
      puts "Testing..."

      result = Client.new(endpoint, @duration, @streams, @samples, @timeout).run
      print_result(result)
    end

    def print_result(result)
      puts
      puts "Latency"
      print_latency("Idle", result.idle_samples)
      print_latency("Download loaded", result.download_samples)
      print_latency("Upload loaded", result.upload_samples)
      puts
      puts "Throughput"
      puts "  %-20s %9.2f Mbps" % ["Download", result.download_mbps]
      puts "  %-20s %9.2f Mbps" % ["Upload", result.upload_mbps]
      puts
      puts "Test duration          %9.2f s" % result.elapsed
    end

    def print_latency(label, samples)
      median = Statistics.median(samples)
      p95 = Statistics.percentile(samples, 0.95)
      jitter = Statistics.jitter(samples)
      puts "  %-20s %9.2f ms  (p95 %7.2f, jitter %6.2f)" % [label, median, p95, jitter]
    end
  end
end
