module Speedtest
  class AgentCLI
    HELP = <<~TEXT
      Usage: speedtest-agent [options]

        --bind ADDRESS   Address to bind (default: 0.0.0.0)
        --port PORT      TCP port (default: 9876)
        --help           Show this help
        --version        Show version
    TEXT

    def self.run(arguments)
      bind_address = "0.0.0.0"
      port = 9876
      index = 0
      while index < arguments.length
        option = arguments[index]
        if option == "--help" || option == "-h"
          puts HELP
          return 0
        elsif option == "--version"
          puts "speedtest-agent #{VERSION}"
          return 0
        elsif option == "--bind"
          raise ConfigError, "missing value for --bind" if arguments[index + 1].nil?
          bind_address = arguments[index + 1]
          index += 2
        elsif option == "--port"
          value = arguments[index + 1]
          raise ConfigError, "missing value for --port" if value.nil?
          begin
            port = Integer(value, 10)
          rescue ArgumentError
            raise ConfigError, "invalid port '#{value}'"
          end
          raise ConfigError, "port must be between 1 and 65535" if port < 1 || port > 65_535
          index += 2
        else
          raise ConfigError, "unknown option '#{option}'"
        end
      end

      Agent.new(bind_address, port).run
      0
    rescue Error => error
      warn "speedtest-agent: #{error.message}"
      1
    rescue SocketError, SystemCallError => error
      warn "speedtest-agent: #{error.message}"
      1
    end
  end
end
