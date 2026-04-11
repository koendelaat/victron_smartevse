#!/bin/bash -ex
# Builds the debug binary AND a statically linked dlv for the target architecture.
#
# dlv does NOT support linux/arm (32-bit). If your Cerbo GX runs a 64-bit kernel
# (Cerbo GX v2 and all later models), use the default TARGET_ARCH=arm64.
# Only use TARGET_ARCH=arm for very old devices that are confirmed 32-bit only.
# In that case dlv remote debugging is impossible and you'd need gdbserver instead.
#
# Usage:
#   ./build_debug.sh               # builds for arm64 (default)
#   TARGET_ARCH=arm64 ./build_debug.sh

TARGET_ARCH="${TARGET_ARCH:-arm}"
GOARM_VAL=""
if [ "$TARGET_ARCH" = "arm" ]; then
  GOARM_VAL=7
  echo "WARNING: dlv does not support linux/arm (32-bit). Only the app binary will be built."
fi

[ ! -d build ] && mkdir build

# ── 1. Build application binary with debug symbols ───────────────────────────
LDFLAGS="-X victron_smartevse/global.Version=$(date "+%Y-%m-%dT%H:%M:%S") -X victron_smartevse/global.BuildTime=$(date "+%Y-%m-%dT%H:%M:%S")"
GOARM="${GOARM_VAL}" GOARCH="${TARGET_ARCH}" GOOS=linux \
  go build -ldflags "$LDFLAGS" -gcflags="all=-N -l" \
  -o build/victron_smartevse_debug app/main.go

echo "   build/victron_smartevse_debug  (linux/${TARGET_ARCH} debug binary)"

# ── 2. Cross-compile dlv for arm64 (statically linked) ───────────────────────
# dlv only supports: linux/amd64, linux/arm64, linux/386, linux/ppc64le
if [ "$TARGET_ARCH" = "arm" ]; then
  echo ""
  echo "⚠️  Skipping dlv build: linux/arm (32-bit) is not supported by dlv."
  echo "   Consider using gdbserver on the target instead."
  exit 0
fi

if [ ! -f build/dlv ]; then
  # Build dlv in a temporary module to avoid "outside main module" errors.
  # go install cannot be used here because we need to cross-compile.
  BUILD_TMP=$(mktemp -d)
  trap 'rm -rf "$BUILD_TMP"' EXIT

  cd "$BUILD_TMP"
  # Init with host arch so 'go get' resolves correctly
  GOARCH= GOARM= GOOS= go mod init _dlv_build
  GOARCH= GOARM= GOOS= go get github.com/go-delve/delve/cmd/dlv@latest

  CGO_ENABLED=0 GOARCH="${TARGET_ARCH}" GOOS=linux \
    go build -ldflags="-extldflags '-static'" \
    -o /home/philips/victron_smartevse/build/dlv \
    github.com/go-delve/delve/cmd/dlv

  cd /home/philips/victron_smartevse
  # trap will clean up BUILD_TMP
fi

echo ""
echo "✅  Build complete:"
echo "   build/victron_smartevse_debug  (linux/${TARGET_ARCH} debug binary)"
echo "   build/dlv                       (linux/${TARGET_ARCH} dlv debugger)"
