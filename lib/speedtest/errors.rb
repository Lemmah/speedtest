module Speedtest
  class Error < StandardError
  end

  class ProtocolError < Error
  end

  class ConfigError < Error
  end
end

