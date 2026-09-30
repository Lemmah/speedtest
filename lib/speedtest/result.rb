module Speedtest
  class TransferResult
    attr_reader :bytes, :elapsed

    def initialize(bytes, elapsed)
      @bytes = bytes
      @elapsed = elapsed
    end
  end

  class TestResult
    attr_reader :idle_samples, :download_samples, :upload_samples
    attr_reader :download_mbps, :upload_mbps, :elapsed

    def initialize(idle_samples, download_samples, upload_samples, download_mbps, upload_mbps, elapsed)
      @idle_samples = idle_samples
      @download_samples = download_samples
      @upload_samples = upload_samples
      @download_mbps = download_mbps
      @upload_mbps = upload_mbps
      @elapsed = elapsed
    end
  end
end
