module Speedtest
  module Clock
    def self.now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def self.sleep_until(deadline)
      remaining = deadline - now
      sleep(remaining) if remaining > 0.0
    end
  end
end

