SPINEL ?= spinel
BUILD_DIR ?= build

.PHONY: all clean test smoke

all: $(BUILD_DIR)/speedtest $(BUILD_DIR)/speedtest-agent

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/speedtest: bin/speedtest lib/speedtest/*.rb | $(BUILD_DIR)
	$(SPINEL) bin/speedtest -o $@

$(BUILD_DIR)/speedtest-agent: bin/speedtest-agent lib/speedtest/*.rb | $(BUILD_DIR)
	$(SPINEL) bin/speedtest-agent -o $@

test:
	ruby test/run.rb

smoke: all
	sh test/native_smoke.sh

clean:
	rm -rf $(BUILD_DIR)

