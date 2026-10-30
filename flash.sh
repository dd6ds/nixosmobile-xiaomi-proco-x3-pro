#!/usr/bin/env bash
#
# flash.sh — installs a Mobile NixOS build on a Xiaomi POCO X3 Pro (vayu)
#
# Run it from the build folder (boot.img, system.img.zst*, SHA256SUMS) or pass
# the folder with -d. The phone must be in fastboot mode (power off, then hold
# Power + Volume-Down) and connected via USB. The bootloader must be unlocked.
#
#   ./flash.sh                 full install: boot + rootfs (ERASES userdata!)
#   ./flash.sh --boot-only     only replace the kernel/initrd (boot partition)
#   ./flash.sh --test-boot     boot boot.img once via RAM, flash nothing
#                              (rootfs must already be on userdata)
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE=full
ASSUME_YES=0
FORCE=0
ERASE_DTBO=0
FLASH_RECOVERY=0
REBOOT=1
EXPECTED_PRODUCT="vayu"

c_info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
c_warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()    { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '3,13p' "$0" | sed 's/^# \{0,1\}//'
  cat <<EOF
Options:
  -d, --dir DIR        folder with the images (default: folder of this script)
      --boot-only      flash only boot.img
      --test-boot      'fastboot boot boot.img' (temporary, nothing is written)
      --recovery       also flash recovery.img to the recovery partition
                       (replaces TWRP/OrangeFox!)
      --erase-dtbo     erase the dtbo partition (try this if the phone bootloops
                       into fastboot; restore by flashing the stock dtbo.img)
      --no-reboot      stay in fastboot after flashing
      --force          skip the device-name check
  -y, --yes            do not ask for confirmation
  -h, --help           this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dir)     DIR="$(cd "$2" && pwd)"; shift 2 ;;
    --boot-only)  MODE=boot; shift ;;
    --test-boot)  MODE=test; shift ;;
    --recovery)   FLASH_RECOVERY=1; shift ;;
    --erase-dtbo) ERASE_DTBO=1; shift ;;
    --no-reboot)  REBOOT=0; shift ;;
    --force)      FORCE=1; shift ;;
    -y|--yes)     ASSUME_YES=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) die "Unknown option: $1 (see --help)" ;;
  esac
done

confirm() {
  [[ $ASSUME_YES -eq 1 ]] && return 0
  read -r -p "$1 [type YES]: " ans
  [[ "$ans" == "YES" ]] || die "Aborted."
}

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------
command -v fastboot >/dev/null || die "fastboot not found (Debian/Ubuntu/Mint: apt install fastboot, Arch/Manjaro: pacman -S android-tools)"
cd "$DIR"
[[ -f boot.img ]] || die "boot.img not found in $DIR"

if [[ -f SHA256SUMS ]]; then
  c_info "Verifying checksums"
  sha256sum --quiet --ignore-missing -c SHA256SUMS || die "Checksum mismatch — download again."
else
  c_warn "No SHA256SUMS, skipping verification"
fi

c_info "Waiting for a device in fastboot mode (Power + Vol-Down) ..."
for _ in $(seq 1 60); do
  fastboot devices | grep -q . && break
  sleep 1
done
fastboot devices | grep -q . || die "No fastboot device found. Check cable / udev rules (try with sudo)."

product="$(fastboot getvar product 2>&1 | awk -F': *' '/^product:/{print $2; exit}')"
unlocked="$(fastboot getvar unlocked 2>&1 | awk -F': *' '/^unlocked:/{print $2; exit}')"
c_info "Device: product='${product:-?}' unlocked='${unlocked:-?}'"
if [[ "$product" != "$EXPECTED_PRODUCT" && $FORCE -eq 0 ]]; then
  die "This is not a POCO X3 Pro (expected '$EXPECTED_PRODUCT'). Use --force to override."
fi
[[ "$unlocked" == "no" ]] && die "Bootloader is locked. Unlock it with the Xiaomi unlock tool first."

# ---------------------------------------------------------------------------
# Test boot (RAM only)
# ---------------------------------------------------------------------------
if [[ $MODE == test ]]; then
  c_info "Booting boot.img temporarily (nothing is flashed)"
  fastboot boot boot.img
  exit 0
fi

# ---------------------------------------------------------------------------
# Prepare rootfs
# ---------------------------------------------------------------------------
SYSIMG=""
cleanup() { [[ -n "$SYSIMG" && "$SYSIMG" == */nixos-vayu-flash.* ]] && rm -f "$SYSIMG" "$SYSIMG.sparse"; }
trap cleanup EXIT

if [[ $MODE == full ]]; then
  command -v zstd >/dev/null || die "zstd not found (apt install zstd / pacman -S zstd)"
  shopt -s nullglob
  parts=(system.img.zst.part-*)
  shopt -u nullglob
  if   [[ -f system.img ]];        then SYSIMG="$DIR/system.img"
  elif [[ -f system.img.zst ]];    then src=(system.img.zst)
  elif [[ ${#parts[@]} -gt 0 ]];   then src=("${parts[@]}")
  else die "No system.img / system.img.zst(.part-*) found"
  fi

  if [[ -z "$SYSIMG" ]]; then
    tmpdir="${TMPDIR:-/var/tmp}"
    SYSIMG="$(mktemp "$tmpdir/nixos-vayu-flash.XXXXXX")"
    c_info "Decompressing rootfs to $SYSIMG"
    cat "${src[@]}" | zstd -d -q -f -o "$SYSIMG"
  fi

  # A sparse image transfers much faster (skips empty blocks).
  FLASHIMG="$SYSIMG"
  if command -v img2simg >/dev/null; then
    c_info "Converting rootfs to Android sparse format"
    img2simg "$SYSIMG" "$SYSIMG.sparse" && FLASHIMG="$SYSIMG.sparse"
  fi

  echo
  c_warn "This ERASES the userdata partition (Android/Ubuntu Touch data, internal storage)!"
  confirm "Continue and flash Mobile NixOS to the phone?"
fi

# ---------------------------------------------------------------------------
# Flash
# ---------------------------------------------------------------------------
if [[ $ERASE_DTBO -eq 1 ]]; then
  c_info "Erasing dtbo"
  fastboot erase dtbo
fi

c_info "Flashing boot"
fastboot flash boot boot.img

if [[ $FLASH_RECOVERY -eq 1 ]]; then
  [[ -f recovery.img ]] || die "recovery.img not in this build"
  c_info "Flashing recovery"
  fastboot flash recovery recovery.img
fi

if [[ $MODE == full ]]; then
  c_info "Flashing rootfs to userdata (this takes several minutes)"
  fastboot flash userdata "$FLASHIMG"
fi

if [[ $REBOOT -eq 1 ]]; then
  c_info "Rebooting"
  fastboot reboot
fi

c_info "Done."
cat <<'EOF'

Default login: user 'nixos', password/PIN '1234' — change it with 'passwd'!
The first boot can take a while (the root filesystem grows to fill userdata).
EOF
