#!/usr/bin/env bash
#
# build.sh — builds a Mobile NixOS image for the Xiaomi POCO X3 Pro (vayu)
#
#   ./build.sh                     # phosh variant, pinned mobile-nixos revision
#   ./build.sh -v minimal          # headless debug variant
#   ./build.sh -r development      # different mobile-nixos branch/commit
#   ./build.sh --docker            # build inside the nixos/nix container (no local Nix needed)
#
# Result: out/nixos-vayu-<variant>-<date>/ with boot.img, system.img.zst(.part-*),
#         flash.sh, SHA256SUMS, build-info.txt
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICE="xiaomi-vayu"
VARIANT="${VARIANT:-phosh}"
MN_REV="${MN_REV:-$(tr -d '[:space:]' < "$HERE/mobile-nixos.rev")}"
MN_REPO="${MN_REPO:-https://github.com/mobile-nixos/mobile-nixos.git}"
OUT_DIR="${OUT_DIR:-$HERE/out}"
WORK_DIR="${WORK_DIR:-$HERE/build}"
BUILD_MODE="${BUILD_MODE:-auto}"   # auto | native | emulated | cross
USE_DOCKER=0
ZSTD_LEVEL="${ZSTD_LEVEL:-10}"
# GitHub release assets must be < 2 GiB -> split bigger files
SPLIT_SIZE="${SPLIT_SIZE:-1900M}"
EXTRA_NIX_ARGS=()

c_info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
c_warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()    { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'
  cat <<EOF
Options:
  -v, --variant NAME   phosh (default) | minimal
  -r, --rev REV        mobile-nixos git revision/branch (default: $(cat "$HERE/mobile-nixos.rev"))
  -o, --out DIR        output directory (default: ./out)
  -m, --mode MODE      auto | native | emulated | cross   (default: auto)
      --docker         run the build inside the nixos/nix docker/podman image
  -h, --help           this help
Environment: VARIANT, MN_REV, MN_REPO, OUT_DIR, WORK_DIR, BUILD_MODE, ZSTD_LEVEL, SPLIT_SIZE
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--variant) VARIANT="$2"; shift 2 ;;
    -r|--rev)     MN_REV="$2"; shift 2 ;;
    -o|--out)     OUT_DIR="$2"; shift 2 ;;
    -m|--mode)    BUILD_MODE="$2"; shift 2 ;;
    --docker)     USE_DOCKER=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) die "Unknown option: $1 (see --help)" ;;
  esac
done

[[ -f "$HERE/config/$VARIANT.nix" ]] || die "Unknown variant '$VARIANT' (config/$VARIANT.nix missing)"

# --------------------------------------------------------------------------
# Optional: re-run this script inside a Nix container
# --------------------------------------------------------------------------
if [[ $USE_DOCKER -eq 1 ]]; then
  engine="$(command -v docker || command -v podman || true)"
  [[ -n "$engine" ]] || die "Neither docker nor podman found."
  c_info "Building inside nixos/nix via $(basename "$engine")"
  exec "$engine" run --rm -i \
    -v "$HERE:/work" -w /work \
    -v nixosmobile-nix-store:/nix \
    -e VARIANT="$VARIANT" -e MN_REV="$MN_REV" -e MN_REPO="$MN_REPO" \
    -e BUILD_MODE="$BUILD_MODE" -e ZSTD_LEVEL="$ZSTD_LEVEL" -e SPLIT_SIZE="$SPLIT_SIZE" \
    -e NIX_CONFIG=$'experimental-features = nix-command flakes\nsandbox = false\nfilter-syscalls = false\nmax-jobs = auto' \
    docker.io/nixos/nix:latest \
    nix shell nixpkgs#git nixpkgs#zstd nixpkgs#coreutils nixpkgs#gnugrep nixpkgs#gnused \
      --command ./build.sh -o /work/out
fi

# --------------------------------------------------------------------------
# Preconditions
# --------------------------------------------------------------------------
for t in nix-build git zstd sha256sum; do
  command -v "$t" >/dev/null || die "'$t' not found. Install Nix (https://nixos.org/download) or use --docker."
done

# Pick how aarch64 code gets built
host_arch="$(uname -m)"
if [[ "$BUILD_MODE" == auto ]]; then
  if [[ "$host_arch" == aarch64 || "$host_arch" == arm64 ]]; then
    BUILD_MODE=native
  elif { nix --extra-experimental-features nix-command config show 2>/dev/null \
          || nix --extra-experimental-features nix-command show-config 2>/dev/null; } \
        | grep -Eq '^(extra-)?platforms = .*aarch64-linux'; then
    BUILD_MODE=emulated
  else
    BUILD_MODE=cross
  fi
fi
case "$BUILD_MODE" in
  native)   ;;
  emulated) EXTRA_NIX_ARGS+=(--argstr system aarch64-linux) ;;  # binfmt/qemu + binary cache
  cross)    c_warn "Cross-compiling from $host_arch: little comes from the binary cache, expect a LONG build (phosh: many hours)." ;;
  *) die "Invalid BUILD_MODE '$BUILD_MODE'" ;;
esac

# --------------------------------------------------------------------------
# Prepare mobile-nixos checkout with our device + config injected
# --------------------------------------------------------------------------
MN_DIR="$WORK_DIR/mobile-nixos"
mkdir -p "$WORK_DIR"
if [[ ! -d "$MN_DIR/.git" ]]; then
  c_info "Cloning mobile-nixos"
  git clone --quiet "$MN_REPO" "$MN_DIR"
fi
c_info "Checking out mobile-nixos @ $MN_REV"
if git -C "$MN_DIR" fetch --quiet origin "$MN_REV" 2>/dev/null; then
  git -C "$MN_DIR" checkout --quiet --force FETCH_HEAD
else
  git -C "$MN_DIR" fetch --quiet origin
  git -C "$MN_DIR" checkout --quiet --force "$MN_REV" || die "mobile-nixos revision '$MN_REV' not found"
fi
git -C "$MN_DIR" clean -fdq
MN_COMMIT="$(git -C "$MN_DIR" rev-parse HEAD)"

rm -rf "$MN_DIR/devices/$DEVICE" "$MN_DIR/vayu"
cp -r "$HERE/device/$DEVICE" "$MN_DIR/devices/$DEVICE"
cp -r "$HERE/config"         "$MN_DIR/vayu"

# --------------------------------------------------------------------------
# Build
# --------------------------------------------------------------------------
c_info "Building variant '$VARIANT' (mode: $BUILD_MODE) — this takes a while"
RESULT="$WORK_DIR/result-$VARIANT"
( cd "$MN_DIR" && nix-build vayu \
    --argstr device "$DEVICE" \
    --argstr variant "$VARIANT" \
    -A outputs.android-fastboot-images \
    --keep-going \
    -o "$RESULT" \
    "${EXTRA_NIX_ARGS[@]}" )

# --------------------------------------------------------------------------
# Package
# --------------------------------------------------------------------------
STAMP="$(date -u +%Y%m%d-%H%M)"
NAME="nixos-vayu-$VARIANT-$STAMP"
PKG="$OUT_DIR/$NAME"
mkdir -p "$PKG"
c_info "Packaging into $PKG"

cp -L "$RESULT/boot.img" "$PKG/boot.img"
[[ -f "$RESULT/recovery.img" ]] && cp -L "$RESULT/recovery.img" "$PKG/recovery.img"

c_info "Compressing system.img (zstd -$ZSTD_LEVEL)"
zstd -T0 -"$ZSTD_LEVEL" -q -f "$RESULT/system.img" -o "$PKG/system.img.zst"
size=$(stat -c %s "$PKG/system.img.zst")
limit=$(numfmt --from=iec "$SPLIT_SIZE")
if (( size > limit )); then
  c_info "Splitting system.img.zst into $SPLIT_SIZE parts"
  split -b "$SPLIT_SIZE" -d -a 2 "$PKG/system.img.zst" "$PKG/system.img.zst.part-"
  rm "$PKG/system.img.zst"
fi

cp "$HERE/flash.sh" "$PKG/flash.sh"
chmod +x "$PKG/flash.sh"

cat > "$PKG/build-info.txt" <<EOF
device:            $DEVICE (Xiaomi POCO X3 Pro)
variant:           $VARIANT
built (UTC):       $STAMP
build mode:        $BUILD_MODE on $host_arch
mobile-nixos:      $MN_COMMIT
this repo:         $(git -C "$HERE" rev-parse HEAD 2>/dev/null || echo "n/a")
system.img (raw):  $(stat -c %s "$RESULT/system.img") bytes
EOF

( cd "$PKG" && sha256sum -- * | grep -v ' SHA256SUMS$' > SHA256SUMS )
c_info "Done:"
ls -lh "$PKG"
echo
echo "Flash with:  cd \"$PKG\" && ./flash.sh"
