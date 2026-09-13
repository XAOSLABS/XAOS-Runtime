#!/usr/bin/env bash
set -euo pipefail

PI_VERSION="${PI_VERSION:-0.85.1}"
NODE_IMAGE="${NODE_IMAGE:-node:22-bookworm-slim}"
RUNTIME_VERSION="${RUNTIME_VERSION:-1}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$ROOT/runtime-build/pi-arm64/work"
OUT="$ROOT/runtime-build/pi-arm64/out"
ROOTFS="$WORK/rootfs"
CONTAINER=""

cleanup() {
  if [[ -n "$CONTAINER" ]]; then docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT
rm -rf "$WORK" "$OUT"
mkdir -p "$ROOTFS" "$OUT"

docker pull --platform linux/arm64 "$NODE_IMAGE" >/dev/null
CONTAINER="$(docker create --platform linux/arm64 "$NODE_IMAGE")"
docker export "$CONTAINER" | tar -xf - -C "$ROOTFS"
docker rm "$CONTAINER" >/dev/null
CONTAINER=""

mkdir -p "$ROOTFS/opt/pi" "$ROOTFS/opt/xaos" "$ROOTFS/root/.pi/agent" "$ROOTFS/workspace" "$ROOTFS/tmp"
# npm itself runs on the build host, but resolves Linux arm64 optional packages.
npm_config_platform=linux npm_config_arch=arm64 npm_config_ignore_scripts=true \
  npm install --prefix "$ROOTFS/opt/pi" --omit=dev --ignore-scripts --no-audit --no-fund \
  "@earendil-works/pi-coding-agent@$PI_VERSION"
cp "$ROOT/packages/xaos-pi-extension/src/index.ts" "$ROOTFS/opt/pi/xaos-extension.ts"
cp "$ROOT/third_party/licenses/pi-MIT.txt" "$ROOTFS/opt/pi/PI-LICENSE-MIT.txt"
cat > "$ROOTFS/usr/local/bin/pi" <<'SH'
#!/bin/sh
exec /usr/local/bin/node /opt/pi/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js "$@"
SH
chmod 0755 "$ROOTFS/usr/local/bin/pi"

# Keep only Linux arm64 runtime material. The published pi package carries
# esbuild/clipboard binaries for many OS/architectures; RPC mode on XAOS only
# needs Linux arm64. npm/yarn/apt docs are build-time baggage as well.
ESBUILD_DIR="$ROOTFS/opt/pi/node_modules/@earendil-works/pi-coding-agent/node_modules/@esbuild"
if [[ -d "$ESBUILD_DIR" ]]; then
  find "$ESBUILD_DIR" -mindepth 1 -maxdepth 1 -type d ! -name linux-arm64 -exec rm -rf {} +
fi
CLIP_DIR="$ROOTFS/opt/pi/node_modules/@earendil-works/pi-coding-agent/node_modules/@mariozechner"
if [[ -d "$CLIP_DIR" ]]; then
  find "$CLIP_DIR" -mindepth 1 -maxdepth 1 -type d \
    ! -name clipboard ! -name clipboard-linux-arm64-gnu -exec rm -rf {} +
fi
rm -rf \
  "$ROOTFS/.dockerenv" \
  "$ROOTFS/root/.npm" \
  "$ROOTFS/opt/yarn-v1.22.22" \
  "$ROOTFS/usr/local/lib/node_modules/npm" \
  "$ROOTFS/usr/share/man" \
  "$ROOTFS/usr/share/locale" \
  "$ROOTFS/usr/share/bash-completion" \
  "$ROOTFS/usr/share/zoneinfo" \
  "$ROOTFS/usr/share/perl5" \
  "$ROOTFS/usr/lib/apt" \
  "$ROOTFS/usr/lib/aarch64-linux-gnu/perl"* \
  "$ROOTFS/var/lib/apt" \
  "$ROOTFS/var/lib/dpkg" \
  "$ROOTFS/var/cache" \
  "$ROOTFS/tmp"/*
rm -f "$ROOTFS/usr/local/bin/npm" "$ROOTFS/usr/local/bin/npx" "$ROOTFS/usr/local/bin/yarn" "$ROOTFS/usr/local/bin/yarnpkg" "$ROOTFS/usr/bin/perl" "$ROOTFS/usr/bin/perl5.36.0" "$ROOTFS/usr/bin/apt" "$ROOTFS/usr/bin/apt-get" "$ROOTFS/usr/bin/apt-cache" "$ROOTFS/usr/bin/dpkg"

ARTIFACT="$OUT/xaos-pi-runtime-arm64-v${RUNTIME_VERSION}.tar.gz"
tar --numeric-owner --owner=0 --group=0 -czf "$ARTIFACT" -C "$ROOTFS" .
SHA="$(sha256sum "$ARTIFACT" | awk '{print $1}')"
SIZE="$(stat -c '%s' "$ARTIFACT")"
cat > "$OUT/xaos-pi-runtime-arm64-v${RUNTIME_VERSION}.manifest.json" <<JSON
{
  "runtimeVersion": "$RUNTIME_VERSION",
  "arch": "arm64",
  "distro": "debian-bookworm-slim",
  "nodeImage": "$NODE_IMAGE",
  "nodeVersion": "22",
  "piVersion": "$PI_VERSION",
  "artifact": "$(basename "$ARTIFACT")",
  "sha256": "$SHA",
  "size": $SIZE
}
JSON
printf '%s  %s\n' "$SHA" "$(basename "$ARTIFACT")" > "$OUT/xaos-pi-runtime-arm64-v${RUNTIME_VERSION}.sha256"
printf 'artifact=%s\nsha256=%s\nsize=%s\n' "$ARTIFACT" "$SHA" "$SIZE"
