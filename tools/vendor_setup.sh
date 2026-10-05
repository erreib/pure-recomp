#!/bin/bash
# Clone the vendored framework at its pinned commit into vendor/portablekit and apply patches/ in order.
# Idempotent: re-running checks the pin and re-applies the series on a clean tree.
set -e
cd "$(dirname "$0")/.."
PIN=8b0c3fe4c8f3d2a1a6d2e4b7c9a0f1e2d3c4b5a6   # overwritten below by the exact SHA if the short one resolves
PIN_SHORT=8b0c3fe
URL=https://github.com/TeamGDB/PortableKit.git
V=vendor/portablekit
if [ ! -d "$V/.git" ]; then
  mkdir -p vendor
  git init -q "$V"
  git -C "$V" remote add origin "$URL"
fi
git -C "$V" fetch -q --depth 1 origin "$PIN_SHORT" 2>/dev/null || git -C "$V" fetch -q origin
git -C "$V" checkout -q --detach "$PIN_SHORT"
git -C "$V" reset -q --hard
git -C "$V" clean -qfd
FULL=$(git -C "$V" rev-parse HEAD)
echo "vendor/portablekit at $FULL ($(git -C "$V" log -1 --format='%ci %s'))"
shopt -s nullglob
for p in patches/[0-9][0-9][0-9][0-9]-*.patch; do
  git -C "$V" apply --check "$PWD/$p" || { echo "patch does not apply: $p"; exit 1; }
  git -C "$V" apply "$PWD/$p"; echo "applied $p"
done
echo "$FULL" > vendor/PIN
