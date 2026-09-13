#!/usr/bin/env bash
# macOS/portable entry point. Image assembly stays on Docker's Linux filesystem.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
volume="${UCONSOLE_DOCKER_VOLUME:-uconsole-universal-build}"
docker volume create "${volume}" >/dev/null
mkdir -p "${ROOT}/out" "${ROOT}/cache"

docker run --rm --privileged --platform linux/arm64 \
  -v /dev:/dev \
  -v "${ROOT}:/repo:ro" \
  -v "${ROOT}/cache:/repo-cache" \
  -v "${ROOT}/out:/repo-out" \
  -v "${volume}:/workspace" \
  -e DEBIAN_FRONTEND=noninteractive \
  -e IMG_SIZE="${IMG_SIZE:-12G}" \
  -e UC_HOSTNAME="${UC_HOSTNAME:-uconsole}" \
  -e TIMEZONE="${TIMEZONE:-America/New_York}" \
  -e LOCALE="${LOCALE:-en_US.UTF-8}" \
  ubuntu:24.04 bash -euc '
    apt-get update -qq
    apt-get install -y -qq curl wget libarchive-tools dosfstools e2fsprogs util-linux fdisk qemu-user-static
    rm -rf /workspace/source
    cp -a /repo /workspace/source
    cd /workspace/source
    OUT_DIR=/workspace/out CACHE_DIR=/repo-cache WORK_DIR=/workspace/work ./build.sh
    rm -rf /repo-out/repo
    cp -a /workspace/out/repo /repo-out/repo
    cp -f /workspace/out/*.img /repo-out/
    cp -f /workspace/out/*.img.sha256 /repo-out/
  '
