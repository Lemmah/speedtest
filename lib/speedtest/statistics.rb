module Speedtest
  module Statistics
    def self.median(values)
      return 0.0 if values.empty?

      sorted = values.sort
      middle = sorted.length / 2
      if sorted.length % 2 == 1
        sorted[middle].to_f
      else
        (sorted[middle - 1].to_f + sorted[middle].to_f) / 2.0
      end
    end

    # Nearest-rank percentile: ceil(p * n), with p in [0, 1].
    def self.percentile(values, probability)
      return 0.0 if values.empty?

      sorted = values.sort
      rank = (probability * sorted.length).ceil
      rank = 1 if rank < 1
      rank = sorted.length if rank > sorted.length
      sorted[rank - 1].to_f
    end

    # Mean absolute difference between consecutive samples.
    def self.jitter(values)
      return 0.0 if values.length < 2

      total = 0.0
      index = 1
      while index < values.length
        total += (values[index].to_f - values[index - 1].to_f).abs
        index += 1
      end
      total / (values.length - 1).to_f
    end

    def self.mbps(bytes, elapsed_seconds)
      return 0.0 if elapsed_seconds <= 0.0

      bytes.to_f * 8.0 / elapsed_seconds / 1_000_000.0
    end
  end
end

