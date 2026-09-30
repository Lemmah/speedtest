module Speedtest
  class Endpoint
    attr_reader :name, :host, :port

    def initialize(name, host, port)
      @name = name
      @host = host
      @port = port
    end

    def address
      if @host.include?(":")
        "[#{@host}]:#{@port}"
      else
        "#{@host}:#{@port}"
      end
    end
  end

  module Config
    DEFAULT_PORT = 9876

    def self.default_path
      override = ENV["SPEEDTEST_CONFIG"]
      return override unless override.nil? || override.empty?

      local = "servers.conf"
      return local if File.exist?(local)

      home = ENV["HOME"]
      return "" if home.nil? || home.empty?

      File.join(home, ".config", "speedtest", "servers.conf")
    end

    def self.load(path)
      endpoints = { "localhost" => Endpoint.new("localhost", "127.0.0.1", DEFAULT_PORT) }
      return endpoints if path.nil? || path.empty? || !File.exist?(path)

      parsed = parse(File.read(path))
      parsed.each { |name, endpoint| endpoints[name] = endpoint }
      endpoints
    end

    # One server per line: NAME HOST PORT. Blank lines and # comments are ignored.
    def self.parse(text)
      endpoints = {}
      line_number = 0
      text.each_line do |raw_line|
        line_number += 1
        line = raw_line.sub(/#.*/, "").strip
        next if line.empty?

        fields = line.split
        unless fields.length == 3
          raise ConfigError, "config line #{line_number}: expected NAME HOST PORT"
        end

        name = fields[0]
        host = fields[1]
        begin
          port = Integer(fields[2], 10)
        rescue ArgumentError
          raise ConfigError, "config line #{line_number}: invalid port"
        end
        if name.empty? || host.empty? || port < 1 || port > 65_535
          raise ConfigError, "config line #{line_number}: invalid server entry"
        end

        endpoints[name] = Endpoint.new(name, host, port)
      end
      endpoints
    end

    def self.direct_endpoint(value)
      if value.start_with?("[")
        closing = value.index("]")
        raise ConfigError, "malformed address: #{value}" if closing.nil? || value[closing + 1] != ":"
        host = value[1...closing]
        port_text = value[(closing + 2)..]
      else
        separator = value.rindex(":")
        raise ConfigError, "malformed address: #{value}" if separator.nil?
        host = value[0...separator]
        port_text = value[(separator + 1)..]
      end

      begin
        port = Integer(port_text, 10)
      rescue ArgumentError
        raise ConfigError, "malformed address: #{value}"
      end
      if host.nil? || host.empty? || port < 1 || port > 65_535
        raise ConfigError, "malformed address: #{value}"
      end

      Endpoint.new(value, host, port)
    end

    def self.resolve(value, endpoints)
      endpoint = endpoints[value]
      return endpoint unless endpoint.nil?
      return direct_endpoint(value) if value.include?(":")

      raise ConfigError, "unknown server '#{value}'"
    end
  end
end
