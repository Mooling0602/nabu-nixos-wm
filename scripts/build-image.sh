#!/usr/bin/env bash
# Build a matching set of flashable nabu images using native cross compilation.
# Usage: bash scripts/build-image.sh [all|esp|rootfs]
# OUT_DIR may name a new output directory; existing artifact files are rejected.
set -euo pipefail
cd "$(dirname "$0")/.."
mode=${1:-all}
case "$mode" in all|esp|rootfs) ;; *)
  echo "usage: $0 [all|esp|rootfs]" >&2; exit 1 ;;
esac
mkdir -p result-images
OUT_DIR=${OUT_DIR:-$(mktemp -d "$PWD/result-images/build-XXXXXX")}
mkdir -p "$OUT_DIR"
OUT_DIR=$(realpath "$OUT_DIR")
for name in esp.img efi-files.zip nabu-rootfs.ext4.img SHA256SUMS; do
  if [ -e "$OUT_DIR/$name" ]; then
    echo "Refusing to overwrite $OUT_DIR/$name; select a new OUT_DIR." >&2
    exit 1
  fi
done

if [ "$mode" != rootfs ]; then
  nix build .#nabu-esp --out-link "$OUT_DIR/nix-esp"
  cp --reflink=auto --sparse=always "$OUT_DIR/nix-esp/esp.img" "$OUT_DIR/esp.img"
  cp "$OUT_DIR/nix-esp/efi-files.zip" "$OUT_DIR/efi-files.zip"
fi
if [ "$mode" = all ] || [ "$mode" = rootfs ]; then
  nix build .#nabu-rootfs --out-link "$OUT_DIR/nix-rootfs"
  cp --reflink=auto --sparse=always \
    "$OUT_DIR/nix-rootfs/nabu-rootfs.ext4.img" "$OUT_DIR/nabu-rootfs.ext4.img"
fi
(
  cd "$OUT_DIR"
  artifacts=()
  for name in esp.img efi-files.zip nabu-rootfs.ext4.img; do
    if [ -f "$name" ]; then artifacts+=("$name"); fi
  done
  sha256sum "${artifacts[@]}" > SHA256SUMS
)
echo "Artifacts: $OUT_DIR"
ls -lh "$OUT_DIR"
