#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
architecture=${1:-$(dpkg --print-architecture)}
version=${2:-}
output_dir=${3:-dist}
package_name=spinel-speedtest

case "$architecture" in
  amd64|arm64) ;;
  *)
    echo "unsupported Debian architecture: $architecture" >&2
    exit 1
    ;;
esac

if [ -z "$version" ]; then
  version=$(sed -n 's/^[[:space:]]*VERSION = "\([^"]*\)"/\1/p' "$project_root/lib/speedtest/version.rb")
fi

case "$version" in
  ""|*[!0-9A-Za-z.+:~_-]*)
    echo "invalid Debian package version: $version" >&2
    exit 1
    ;;
esac

if [ ! -x "$project_root/build/speedtest" ] || [ ! -x "$project_root/build/speedtest-agent" ]; then
  echo "native binaries are missing; run make with SPINEL first" >&2
  exit 1
fi

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT HUP INT TERM
package_root="$staging/${package_name}_${version}_${architecture}"

install -d \
  "$package_root/DEBIAN" \
  "$package_root/usr/bin" \
  "$package_root/usr/lib/systemd/system" \
  "$package_root/usr/share/doc/$package_name/examples"

install -m 0755 "$project_root/build/speedtest" "$package_root/usr/bin/speedtest"
install -m 0755 "$project_root/build/speedtest-agent" "$package_root/usr/bin/speedtest-agent"
install -m 0644 "$project_root/packaging/speedtest-agent.service" \
  "$package_root/usr/lib/systemd/system/speedtest-agent.service"
install -m 0644 "$project_root/config/servers.conf.example" \
  "$package_root/usr/share/doc/$package_name/examples/servers.conf"
install -m 0644 "$project_root/README.md" "$package_root/usr/share/doc/$package_name/README.md"
install -m 0644 "$project_root/LICENSE" "$package_root/usr/share/doc/$package_name/copyright"
gzip -9n "$package_root/usr/share/doc/$package_name/README.md"

installed_size=$(du -sk "$package_root/usr" | awk '{print $1}')
homepage=${PACKAGE_HOMEPAGE:-https://github.com/}

cat > "$package_root/DEBIAN/control" <<EOF
Package: $package_name
Version: $version
Section: net
Priority: optional
Architecture: $architecture
Installed-Size: $installed_size
Maintainer: Speedtest Contributors <noreply@github.com>
Depends: adduser, libc6 (>= 2.36)
Conflicts: speedtest
Homepage: $homepage
Description: Distributed network speed-test CLI and agent
 Measures idle and loaded latency, jitter, and duration-based upload and
 download throughput between the included CLI and a remote agent.
EOF

cat > "$package_root/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e

if ! getent passwd speedtest >/dev/null; then
  adduser --system --group --no-create-home --home /nonexistent speedtest
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload >/dev/null 2>&1 || true
fi
EOF

cat > "$package_root/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e

if [ "$1" = remove ] && command -v systemctl >/dev/null 2>&1; then
  systemctl disable --now speedtest-agent.service >/dev/null 2>&1 || true
fi
EOF

cat > "$package_root/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e

if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload >/dev/null 2>&1 || true
fi
EOF

chmod 0755 \
  "$package_root/DEBIAN/postinst" \
  "$package_root/DEBIAN/prerm" \
  "$package_root/DEBIAN/postrm"

mkdir -p "$project_root/$output_dir"
output="$project_root/$output_dir/${package_name}_${version}_${architecture}.deb"
dpkg-deb --root-owner-group --build "$package_root" "$output"
echo "$output"

