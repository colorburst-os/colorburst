#!/usr/bin/env bash
#
# Build/refresh runtime/ — the crosvm bundle that start-vm.sh runs.
# See RUNNING-VM.md section 3 for the reasoning; this is that recipe.
#
#   ./tools/build-runtime.sh [path-to-chromium-os-checkout]
#
# Assumes the chromium-os dev environment has already built crosvm and
# minigbm (env CROS_IMAGE=cros-crosvm ./cros-sdk.sh ... — see CROSVM.md),
# and that the cros-crosvm Docker image exists (it supplies virglrenderer).
set -euo pipefail

CB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:-$CB/../chromium-os}"
OUT="$CB/runtime"

CROSVM_BIN="$SRC/chromiumos/.cache/crosvm-target/chromeos/crosvm"
MINIGBM="$SRC/chromiumos/.cache/minigbm/lib/libminigbm.so.1.0.0"

for f in "$CROSVM_BIN" "$MINIGBM"; do
    [ -f "$f" ] || { echo "missing: $f" >&2
        echo "Build it first — see chromium-os/CROSVM.md." >&2; exit 1; }
done

rm -rf "$OUT"
mkdir -p "$OUT/bin" "$OUT/lib"
install -m755 "$CROSVM_BIN" "$OUT/bin/crosvm"
# minigbm's SONAME is libgbm.so.1; it is what crosvm links against.
install -m644 "$MINIGBM" "$OUT/lib/libgbm.so.1"

# virglrenderer comes from the build container's distro packages.
cid="$(docker create cros-crosvm:latest)"
trap 'docker rm "$cid" >/dev/null' EXIT
# -L: the packaged path is a symlink chain; copy the real object.
docker cp -L "$cid:/usr/lib/x86_64-linux-gnu/libvirglrenderer.so.1" \
             "$OUT/lib/libvirglrenderer.so.1"
chmod 644 "$OUT/lib/libvirglrenderer.so.1"

echo "=== bundle:"
find "$OUT" -type f -printf '%10s  %p\n'

echo "=== check 1: nothing unresolved"
if LD_LIBRARY_PATH="$OUT/lib" ldd "$OUT/bin/crosvm" | grep 'not found'; then
    echo "FAIL: unresolved libraries" >&2; exit 1
fi

echo "=== check 2: the host owns the GL stack"
# libEGL / libGL / libdrm / libvulkan / the DRI drivers must resolve to the
# host, never into the bundle: a bundled Mesa silently falls back to llvmpipe.
if LD_LIBRARY_PATH="$OUT/lib" ldd "$OUT/lib/libvirglrenderer.so.1" \
     | grep -E 'libEGL|libGL|libdrm|libvulkan|libepoxy' | grep -F "$OUT"; then
    echo "FAIL: GL libraries are being taken from the bundle" >&2; exit 1
fi

echo "OK — runtime/ is ready ($(du -sh "$OUT" | cut -f1))"
