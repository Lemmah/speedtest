# speedtest

`speedtest` is a small distributed network diagnostic tool. A native CLI on
your computer talks directly to a native agent on a server and measures the
path between those two machines: idle RTT, jitter, p95 RTT, download and upload
throughput, and RTT while each direction is loaded.

Both executables are Ruby programs compiled ahead of time by
[Spinel](https://github.com/matz/spinel). They have no Ruby runtime or gem
dependency after compilation.

> **Security warning:** the agent has no authentication or encryption. Anyone
> who can reach it can consume server bandwidth and CPU. Restrict TCP port 9876
> with a firewall, security group, VPN, or source-IP allowlist. Do not expose it
> openly unless that risk is acceptable.

## Architecture

```text
                         independent control TCP connection
                    PING <----------------------------> PONG
                   /                                      \
  speedtest CLI --+-- N download TCP streams ------------+-- speedtest-agent
                   \-- N upload TCP streams --------------/
                       duration-based, 64 KiB buffers
```

The control connection remains independent of bulk streams. The CLI sends
application pings on it while the bulk streams are active; those RTTs expose
bufferbloat-like loaded latency. Each throughput direction defaults to 10
seconds and four concurrent streams.

## Requirements and Spinel compatibility

This repository is tested with **Spinel 2026.09.12** (git tag and compiler
version `2026.09.12`). That release documents and implements the subset used
here: POSIX TCP sockets, `Thread`, scheduler-aware blocking IO,
`Process.clock_gettime(Process::CLOCK_MONOTONIC)`, files, and signal traps.
There are no third-party Ruby dependencies.

Install the pinned compiler from source:

```sh
git clone --depth 1 --branch 2026.09.12 https://github.com/matz/spinel.git
cd spinel
make deps
make -j4
./bin/spinel --version
```

`make deps` downloads Spinel's pinned Prism/RBS parser sources. A C compiler,
`make`, `git`, and `curl` are required. Spinel supports Linux (x86-64 and
arm64) and macOS (Intel and Apple Silicon); use WSL on Windows.

## Build

From this repository, point `make` at the compiler you just built:

```sh
make SPINEL=/absolute/path/to/spinel/bin/spinel
```

The native executables are:

```text
build/speedtest
build/speedtest-agent
```

Alternatively install Spinel on `PATH` (`make install PREFIX="$HOME/.local"`
inside its checkout) and run plain `make` here.

Binaries are native to the OS and CPU on which they are built. A macOS ARM64
binary is not a Linux binary; compile the agent on Linux (or generate C and
finish the build with Spinel's runtime/toolchain on Linux) for a Linux VM.

## First run

Start an agent:

```sh
./build/speedtest-agent --bind 127.0.0.1 --port 9876
```

In another terminal:

```sh
./build/speedtest test localhost
```

For a remote agent:

```sh
./build/speedtest test 203.0.113.10:9876
./build/speedtest test fra1 --duration 10 --streams 8
```

Useful commands:

```sh
./build/speedtest --help
./build/speedtest --version
./build/speedtest servers
./build/speedtest-agent --help
```

Durations may be fractional, which is convenient for smoke tests. Valid
ranges are 0.1–60 seconds, 1–16 streams, and 2–100 idle samples. The default
connect timeout is five seconds and can be changed with `--timeout`.

## Server registry

The built-in `localhost` entry is always present. The CLI loads the first
configured path in this order:

1. `--config PATH`
2. `SPEEDTEST_CONFIG`
3. `servers.conf` in the current directory
4. `$HOME/.config/speedtest/servers.conf`

The deliberately small format is `NAME HOST PORT`, one server per line:

```text
# NAME HOST PORT
home 192.168.1.20 9876
fra1 fra1.example.com 9876
lon1 lon1.example.com 9876
```

See `config/servers.conf.example`. Inline `#` comments and blank lines are
allowed. Direct IPv6 addresses use `[2001:db8::1]:9876`.

## Agent deployment with systemd

### Debian packages

The `Debian packages` GitHub Actions workflow builds native Debian 12 packages
for `amd64` (x86-64) and `arm64`. Run it manually from the Actions tab, or push
a version tag matching `lib/speedtest/version.rb`, for example:

```sh
git tag v0.1.0
git push origin v0.1.0
```

Manual runs publish downloadable workflow artifacts. Tag runs additionally
create or update the GitHub release with both `.deb` files and `SHA256SUMS`.
Install the package matching the server architecture:

```sh
sudo apt install ./spinel-speedtest_0.1.0_arm64.deb
# or: sudo apt install ./spinel-speedtest_0.1.0_amd64.deb
sudo systemctl enable --now speedtest-agent
```

The package deliberately does not enable or start the unauthenticated agent
automatically. It installs both executables under `/usr/bin`, creates the
unprivileged `speedtest` system user, and installs the service under
`/usr/lib/systemd/system`.

### Manual installation

Build the agent on the target Linux architecture, create an unprivileged user,
and install the provided service:

```sh
sudo useradd --system --no-create-home --shell /usr/sbin/nologin speedtest
sudo install -m 0755 build/speedtest-agent /usr/local/bin/speedtest-agent
sudo install -m 0644 deploy/speedtest-agent.service /etc/systemd/system/speedtest-agent.service
sudo systemctl daemon-reload
sudo systemctl enable --now speedtest-agent
sudo systemctl status speedtest-agent
```

Permit inbound TCP/9876 only from intended client addresses. For example, use
your cloud firewall/security group and host firewall. The included unit runs as
the unprivileged `speedtest` user, restarts on failure, and applies basic
systemd hardening.

## Measurement method

- All elapsed intervals and RTTs use the monotonic clock, not wall time.
- Idle latency is the median of 10 application `PING`/`PONG` RTT samples by
  default. p95 uses the nearest-rank definition.
- Jitter is the mean absolute difference between consecutive RTT samples:
  `mean(abs(rtt[n] - rtt[n-1]))`.
- Download and upload each run for the requested duration. Every stream reuses
  a 64 KiB buffer. Aggregate Mbps is
  `total_bytes * 8 / longest_stream_elapsed / 1,000,000`.
- A `READY`/`GO` barrier prepares all bulk connections before their shared
  monotonic start time.
- Loaded latency is sampled over the separate control connection for the full
  download or upload phase. It does not share a socket with payload data.

The output is a path measurement, not a universal Internet-speed score. TCP
congestion control, stream count, duration, client/server CPU, TCP buffer
sizes, Wi-Fi, routing, competing traffic, ISP shaping, and the absence of TLS
all influence it.

## Wire protocol (version 1)

Control lines are UTF-8/ASCII terminated by `\n` and limited to 1024 bytes.
Readers never assume a TCP read equals a protocol message. Every connection
starts with:

```text
C: HELLO 1
S: OK 1
```

Control connection:

```text
C: PING
S: PONG
C: QUIT
S: BYE
```

Download bulk connection:

```text
C: DOWNLOAD <duration-ms>
S: READY
C: GO
S: <raw bytes until the server closes this bulk connection>
```

Upload bulk connection (repeated chunks, then terminator):

```text
C: UPLOAD <duration-ms>
S: READY
C: GO
C: CHUNK <byte-count>\n<exactly byte-count raw bytes>
C: DONE
S: RESULT <total-bytes-received>
```

The implementation loops around writes and exact-size reads, so partial IO is
handled. Errors are `ERROR <category> <message>`. Throughput streams use their
own connections and close after one test; the control connection closes with
`QUIT`.

### Spinel-specific compromise

Spinel 2026.09.12 provides `IO#readpartial` and `BasicSocket#shutdown`, but the
compiler's dynamic receiver dispatch rejected those calls inside this
application's threaded bulk-worker shape during the real native smoke test.
The implementation therefore uses supported blocking `IO#read` and explicit
upload chunk framing instead. This preserves bounded memory, partial-read
correctness, duration-based tests, concurrent streams, and native execution.

There is no TLS or authentication in this MVP. DNS and TCP connect timeout are
handled by the platform resolver plus the CLI's bounded connection thread;
there is no per-read stall timeout once a test has begun.

## Development and verification

Pure logic tests run under CRuby:

```sh
make test
```

They cover decimal-Mbps calculation, median, p95, jitter, protocol parsing,
configuration parsing, direct IPv4, and bracketed IPv6.

Compile and run the native end-to-end test:

```sh
make SPINEL=/absolute/path/to/spinel/bin/spinel
make smoke SPINEL=/absolute/path/to/spinel/bin/spinel
```

The smoke script starts the **compiled** agent, runs the **compiled** CLI with
two streams, checks every measurement, then performs another complete test
against the same agent to verify repeated-test handling. It binds localhost
port 19876 by default; override with `SPEEDTEST_SMOKE_PORT`.
