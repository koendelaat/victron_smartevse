#!/bin/bash -ex
# Deploys the debug binary to a Venus OS / Cerbo GX and starts a dlv headless
# debug server when supported by target architecture.
#
# If the target is linux/arm (32-bit), dlv is not supported and debug attach is
# skipped with a clear message.
#
# Usage:
#   CERBO_HOST=192.168.1.x ./deploy_debug.sh

CERBO_HOST="${CERBO_HOST:-127.0.0.1}"
CERBO_USER="${CERBO_USER:-root}"
CERBO_SSH_PORT="${CERBO_SSH_PORT:-2222}"
REMOTE_DIR="/data/victron_smartevse"
DLV_PORT=2345
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

SSH_OPTS="-p ${CERBO_SSH_PORT} -o StrictHostKeyChecking=no"

echo "------------------------------------------"
echo " Target : ${CERBO_USER}@${CERBO_HOST}:${CERBO_SSH_PORT}"
echo " Remote : ${REMOTE_DIR}"
echo " dlv    : :${DLV_PORT}"
echo "------------------------------------------"

# 1) Detect remote architecture first (prevents Exec format errors)
REMOTE_UNAME=$(ssh ${SSH_OPTS} "${CERBO_USER}@${CERBO_HOST}" "uname -m")
case "${REMOTE_UNAME}" in
  aarch64|arm64)
    TARGET_ARCH="arm64"
    DLV_SUPPORTED=1
    ;;
  armv7l|armv6l|armv5*|arm)
    TARGET_ARCH="arm"
    DLV_SUPPORTED=0
    ;;
  *)
    echo "ERROR: Unsupported remote architecture '${REMOTE_UNAME}'."
    echo "Known mappings: aarch64->arm64, armv7l/armv6l->arm"
    exit 1
    ;;
esac

echo "Detected remote arch: ${REMOTE_UNAME} -> ${TARGET_ARCH}"

# 2) Ensure local binaries are built for this exact target arch
if [ ! -f "${PROJECT_DIR}/build/victron_smartevse_debug" ]; then
  TARGET_ARCH="${TARGET_ARCH}" "${PROJECT_DIR}/build_debug.sh"
else
  if [ "${TARGET_ARCH}" = "arm64" ]; then
    if ! file "${PROJECT_DIR}/build/victron_smartevse_debug" | grep -q "ARM aarch64"; then
      TARGET_ARCH="${TARGET_ARCH}" "${PROJECT_DIR}/build_debug.sh"
    fi
  else
    if ! file "${PROJECT_DIR}/build/victron_smartevse_debug" | grep -q "ARM"; then
      TARGET_ARCH="${TARGET_ARCH}" "${PROJECT_DIR}/build_debug.sh"
    fi
  fi
fi

if [ "${DLV_SUPPORTED}" -eq 1 ]; then
  if [ ! -f "${PROJECT_DIR}/build/dlv" ] || ! file "${PROJECT_DIR}/build/dlv" | grep -q "ARM aarch64"; then
    TARGET_ARCH="${TARGET_ARCH}" "${PROJECT_DIR}/build_debug.sh"
  fi
fi

# 3) Ensure remote directory exists
ssh ${SSH_OPTS} "${CERBO_USER}@${CERBO_HOST}" "mkdir -p ${REMOTE_DIR}"

# 4) Copy artifacts
if [ "${DLV_SUPPORTED}" -eq 1 ]; then
  scp -P "${CERBO_SSH_PORT}" \
      "${PROJECT_DIR}/build/victron_smartevse_debug" \
      "${PROJECT_DIR}/build/dlv" \
      "${CERBO_USER}@${CERBO_HOST}:${REMOTE_DIR}/"

  ssh ${SSH_OPTS} "${CERBO_USER}@${CERBO_HOST}" \
      "chmod +x ${REMOTE_DIR}/victron_smartevse_debug ${REMOTE_DIR}/dlv"
else
  scp -P "${CERBO_SSH_PORT}" \
      "${PROJECT_DIR}/build/victron_smartevse_debug" \
      "${CERBO_USER}@${CERBO_HOST}:${REMOTE_DIR}/"

  ssh ${SSH_OPTS} "${CERBO_USER}@${CERBO_HOST}" \
      "chmod +x ${REMOTE_DIR}/victron_smartevse_debug"
fi

# 5) Restart debug server when supported
if [ "${DLV_SUPPORTED}" -eq 1 ]; then
  ssh ${SSH_OPTS} "${CERBO_USER}@${CERBO_HOST}" \
      "pkill -f 'dlv exec' 2>/dev/null || true"

  ssh ${SSH_OPTS} "${CERBO_USER}@${CERBO_HOST}" \
      "nohup ${REMOTE_DIR}/dlv exec ${REMOTE_DIR}/victron_smartevse_debug \
          --headless \
          --listen=:${DLV_PORT} \
          --api-version=2 \
          --only-same-user=false \
          --accept-multiclient \
          -- \
          > ${REMOTE_DIR}/dlv.log 2>&1 &"

  echo ""
  echo "dlv is listening on ${CERBO_HOST}:${DLV_PORT}"
  echo ""
  echo "Open an SSH tunnel in another terminal (keep it open):"
  echo "ssh -L ${DLV_PORT}:localhost:${DLV_PORT} ${CERBO_USER}@${CERBO_HOST} -p ${CERBO_SSH_PORT} -N"
  echo ""
  echo "Then click the Debug button for 'Debug on Cerbo GX' in GoLand."
else
  echo ""
  echo "Target is 32-bit ARM (${REMOTE_UNAME}). dlv is not supported on linux/arm."
  echo "Binary was deployed only: ${REMOTE_DIR}/victron_smartevse_debug"
  echo "Use logs/print debugging or switch to gdbserver workflow for this device."
fi
