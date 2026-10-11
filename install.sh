#!/usr/bin/env bash
#
# install.sh — install NixOS with this configuration, from the NixOS live ISO.
#
# Boot the NixOS installer USB stick in UEFI mode, connect to the network (nmtui), then:
#     git clone <this repository> nixos-config && cd nixos-config && sudo ./install.sh
#
# It asks for the hostname, the user name and the user's password, then:
#   1. picks the disk named `target` in host/disks.nix, matched by serial number (never by nvme0n1/nvme1n1:
#      those names can swap between boots), shows what is on it and asks you to type ERASE. Disks listed
#      under `protected` in host/disks.nix, USB disks (the installer stick) and disks with anything mounted
#      are refused outright, whatever you answer; nothing on them is ever written.
#   2. partitions the target: 1 GiB EFI system partition (/boot/efi), swap, ext4 root (labels NIXBOOT,
#      nixos-swap, nixos), and mounts it at /mnt
#   3. generates host/hardware-configuration.nix for those partitions and checks that every device it
#      references is on the target disk
#   4. copies this repository to /mnt/home/<user>/nixos-config and writes vars.nix
#   5. asks whether to run nixos-install now. After installing it sets the user's password (root stays
#      locked; the user has sudo), gives the repository to the user, copies the live system's saved Wi-Fi
#      networks, checks the UEFI boot entries ("NixOS", exactly once) and offers to reboot.
# On the first boot the nixos-first-boot service finishes the per-user setup in the background (zinit,
# Neovim plugins, Mason tools, rustup, vibium, nix-index) as soon as there is network.
#
# Re-running after a failed nixos-install offers to reuse the partitions still mounted at /mnt.
#
# Options:
#   --disk PATH     install onto this disk instead of host/disks.nix's target (protected disks are still refused)
#   --swap GIB      size of the swap partition in GiB (default 8; 0 = no swap partition, zram only)
#   -h, --help      this text

set -euo pipefail

SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DISK_ARG=""
SWAP_GIB=8
ESP_MIB=1024
MIN_ROOT_GIB=30

# groups the configuration gives the user (host/configuration.nix); checked after the install
EXPECTED_GROUPS="wheel networkmanager video input kvm libvirtd wireshark"

# ----------------------------------------------------------------------------- helpers

c_info=$'\033[1;34m' c_ok=$'\033[1;32m' c_warn=$'\033[1;33m' c_err=$'\033[1;31m' c_off=$'\033[0m'
info() { printf '\n%s==>%s %s\n' "$c_info" "$c_off" "$*"; }
ok() { printf '%s  ✓%s %s\n' "$c_ok" "$c_off" "$*"; }
warn() { printf '%s  !%s %s\n' "$c_warn" "$c_off" "$*"; }
die() {
  printf '%serror:%s %s\n' "$c_err" "$c_off" "$*" >&2
  exit 1
}

# ask "question" [default y|n] -> 0 for yes
ask() {
  local prompt="$1" default="${2:-n}" answer
  if [ "$default" = y ]; then prompt="$prompt [Y/n] "; else prompt="$prompt [y/N] "; fi
  read -r -p "$prompt" answer || die "no input"
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[Yy] ]]
}

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; }

# flakes + nix-command for every nix call in this script, whatever the live system has configured
export NIX_CONFIG="experimental-features = nix-command flakes"

# lsblk column for one device, surrounding blanks removed (NVMe serials are space-padded, SIZE is right-aligned)
attr() { lsblk -dno "$2" "$1" 2>/dev/null | head -n1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }

# /dev/nvme0n1p3 -> /dev/nvme0n1 (empty for a whole disk or an unknown device)
parent_disk() {
  local pk
  pk="$(lsblk -no PKNAME "$1" 2>/dev/null | head -n1 | sed 's/[[:space:]]*$//')"
  [ -n "$pk" ] && echo "/dev/$pk"
}

# partition N of a disk: nvme0n1 -> nvme0n1p1, sda -> sda1
part_dev() { if [[ "$1" =~ [0-9]$ ]]; then echo "${1}p$2"; else echo "$1$2"; fi; }

# ----------------------------------------------------------------------------- arguments

if [ "$(id -u)" != 0 ]; then
  exec sudo bash "$0" "$@"
fi

while [ $# -gt 0 ]; do
  case "$1" in
  --disk)
    [ $# -ge 2 ] || die "--disk needs a device"
    DISK_ARG="$2"
    shift
    ;;
  --swap)
    [ $# -ge 2 ] && [[ "$2" =~ ^[0-9]+$ ]] || die "--swap needs a size in GiB (0 for none)"
    SWAP_GIB="$2"
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) die "unknown option: $1 (see --help)" ;;
  esac
  shift
done

# ----------------------------------------------------------------------------- preflight

info "Preflight checks"
[ -e /etc/NIXOS ] || die "this is not NixOS: boot the NixOS live ISO and run this from there"
# the live ISO runs from RAM (tmpfs root) with the image at /iso; an installed system has neither
if [ ! -d /iso ] && ! findmnt -no FSTYPE / | grep -qxE 'tmpfs|overlay'; then
  die "this looks like an installed system, not the live ISO. install.sh repartitions a disk and is only
       meant for the live ISO; on an installed system use: sudo nixos-rebuild switch --flake ~/nixos-config"
fi
[ -d /sys/firmware/efi/efivars ] ||
  die "the live ISO was booted in legacy BIOS mode; reboot it in UEFI mode (GRUB is installed for UEFI)"
[ -f "$SOURCE/flake.nix" ] && [ -f "$SOURCE/host/disks.nix" ] || die "flake.nix or host/disks.nix missing next to this script ($SOURCE)"
ok "NixOS live ISO, UEFI mode, root"

if command -v curl >/dev/null && ! curl -fsS --max-time 15 -o /dev/null https://cache.nixos.org/nix-cache-info; then
  die "no network: connect first (nmtui for Wi-Fi), the install downloads everything from the internet"
fi
ok "network"

# tools; anything missing from the ISO comes from nixpkgs
declare -A tool_pkg=(
  [parted]=parted [wipefs]=util-linux [lsblk]=util-linux [blkid]=util-linux [findmnt]=util-linux
  [mkfs.fat]=dosfstools [mkfs.ext4]=e2fsprogs [mkswap]=util-linux [efibootmgr]=efibootmgr [udevadm]=systemd
)
for t in "${!tool_pkg[@]}"; do
  command -v "$t" >/dev/null && continue
  info "fetching ${tool_pkg[$t]} for $t"
  out="$(nix build --no-link --print-out-paths "nixpkgs#${tool_pkg[$t]}" | head -n1)" || die "could not get $t"
  PATH="$out/bin:$out/sbin:$PATH"
  command -v "$t" >/dev/null || die "$t not found"
done
for t in nix nixos-generate-config nixos-install nixos-enter; do
  command -v "$t" >/dev/null || die "$t not found (is this the NixOS installer?)"
done
ok "tools"

# disk choices from host/disks.nix
disks_nix() { nix eval --raw --file "$SOURCE/host/disks.nix" "$@"; }
TARGET_SERIAL="$(disks_nix target.serial)" || die "could not read target.serial from host/disks.nix"
TARGET_DESC="$(disks_nix target.description 2>/dev/null || echo "$TARGET_SERIAL")"
PROTECTED_SERIALS="$(disks_nix protected --apply 'ps: builtins.concatStringsSep " " (map (p: p.serial) ps)')" ||
  die "could not read the protected disks from host/disks.nix"
PROTECTED_DESC="$(disks_nix protected --apply 'ps: builtins.concatStringsSep ", " (map (p: p.description or p.serial) ps)')"

# ----------------------------------------------------------------------------- names and password

info "Machine and user"
while :; do
  read -r -p "Hostname: " HOST || die "no input"
  [[ "$HOST" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] && break
  warn "letters, digits and '-' only (not at the start or end), at most 63 characters"
done
while :; do
  read -r -p "User name: " USERNAME || die "no input"
  if [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    warn "lowercase letters, digits, '_' and '-', starting with a letter or '_', at most 32 characters"
  elif [[ " root nixos nobody daemon bin sys messagebus systemd-network sshd nixbld " == *" $USERNAME "* ]]; then
    warn "$USERNAME is a system account name; pick another"
  else
    break
  fi
done
while :; do
  read -r -s -p "Password for $USERNAME: " PASSWORD || die "no input"
  echo
  [ -n "$PASSWORD" ] || { warn "the password cannot be empty"; continue; }
  read -r -s -p "Repeat the password: " password2 || die "no input"
  echo
  [ "$PASSWORD" = "$password2" ] && break
  warn "the passwords do not match"
done
unset password2
ok "host $HOST, user $USERNAME"

# ----------------------------------------------------------------------------- disk selection

info "Disks"

# protected: listed in host/disks.nix by serial (checked against lsblk and /dev/disk/by-id)
is_protected() {
  local dev="$1" serial s link
  serial="$(attr "$dev" SERIAL)"
  for s in $PROTECTED_SERIALS; do
    [ -n "$serial" ] && [ "${serial^^}" = "${s^^}" ] && return 0
    for link in /dev/disk/by-id/*"$s"*; do
      [ -e "$link" ] && [ "$(readlink -f "$link")" = "$dev" ] && return 0
    done
  done
  return 1
}

ISO_DISK=""
iso_src="$(findmnt -no SOURCE /iso 2>/dev/null || true)"
[ -n "$iso_src" ] && [ -b "$iso_src" ] && ISO_DISK="$(parent_disk "$iso_src" || true)"

# why a disk must not be installed onto (empty: it may be). Mounts under /mnt are not counted here: those
# are a previous run of this script, handled below.
refusal() {
  local dev="$1" tran rm mounts
  [ "$(attr "$dev" TYPE)" = disk ] || { echo "not a whole disk"; return; }
  is_protected "$dev" && { echo "protected in host/disks.nix"; return; }
  [ -n "$ISO_DISK" ] && [ "$dev" = "$ISO_DISK" ] && { echo "the live ISO is running from it"; return; }
  tran="$(attr "$dev" TRAN)" rm="$(attr "$dev" RM)"
  { [ "$tran" = usb ] || [ "$rm" = 1 ]; } && { echo "USB/removable disk"; return; }
  # active swap ([SWAP]) does not count: swapping is turned off before anything is written
  mounts="$(lsblk -nlpo MOUNTPOINTS "$dev" 2>/dev/null | grep -v '^$' | grep -v '^/mnt' | grep -vx '\[SWAP\]' || true)"
  [ -n "$mounts" ] && { echo "in use (mounted or swap: $(echo $mounts))"; return; }
  echo ""
}

mapfile -t ALL_DISKS < <(lsblk -dnpo NAME,TYPE | awk '$2 == "disk" { print $1 }')
DISK=""
printf '  %-14s %-9s %-20s %-30s %s\n' DEVICE SIZE SERIAL MODEL STATUS
for d in "${ALL_DISKS[@]}"; do
  why="$(refusal "$d")"
  serial="$(attr "$d" SERIAL)"
  if [ -n "$why" ]; then status="refused: $why"; else status="ok"; fi
  [ -n "$serial" ] && [ "${serial^^}" = "${TARGET_SERIAL^^}" ] && status="$status (target in host/disks.nix)"
  printf '  %-14s %-9s %-20s %-30s %s\n' "$d" "$(attr "$d" SIZE)" "${serial:--}" "$(attr "$d" MODEL)" "$status"
  if [ -z "$DISK_ARG" ] && [ -n "$serial" ] && [ "${serial^^}" = "${TARGET_SERIAL^^}" ]; then DISK="$d"; fi
done

for s in $PROTECTED_SERIALS; do
  found=0
  for d in "${ALL_DISKS[@]}"; do is_protected "$d" && [ "${s^^}" = "$(attr "$d" SERIAL | tr a-z A-Z)" ] && found=1; done
  [ "$found" = 1 ] || warn "protected disk with serial $s not found (not connected?)"
done

if [ -n "$DISK_ARG" ]; then
  DISK="$(readlink -f "$DISK_ARG")"
  [ -b "$DISK" ] || die "$DISK_ARG is not a block device"
elif [ -z "$DISK" ]; then
  warn "the target disk from host/disks.nix ($TARGET_DESC, serial $TARGET_SERIAL) is not in this machine"
  mapfile -t CANDIDATES < <(for d in "${ALL_DISKS[@]}"; do [ -z "$(refusal "$d")" ] && echo "$d"; done)
  [ "${#CANDIDATES[@]}" -gt 0 ] || die "no disk is eligible for the install"
  echo "  Eligible disks:"
  for i in "${!CANDIDATES[@]}"; do
    printf '    %d) %s  %s  %s  serial %s\n' "$((i + 1))" "${CANDIDATES[$i]}" "$(attr "${CANDIDATES[$i]}" SIZE)" \
      "$(attr "${CANDIDATES[$i]}" MODEL)" "$(attr "${CANDIDATES[$i]}" SERIAL)"
  done
  read -r -p "  Install onto which disk? (number, Enter to abort) " pick || die "no input"
  [[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le "${#CANDIDATES[@]}" ] || die "aborted"
  DISK="${CANDIDATES[$((pick - 1))]}"
  warn "to make this permanent, put its serial ($(attr "$DISK" SERIAL)) into host/disks.nix as the target"
fi

why="$(refusal "$DISK")"
[ -z "$why" ] || die "refusing to install onto $DISK: $why"
DISK_SERIAL="$(attr "$DISK" SERIAL)"
DISK_NAME="$DISK ($(attr "$DISK" MODEL), $(attr "$DISK" SIZE), serial ${DISK_SERIAL:-none})"
ok "target: $DISK_NAME"
ok "protected, never touched: ${PROTECTED_DESC:-none}"

# ----------------------------------------------------------------------------- previous run?

REUSE=0
if mountpoint -q /mnt; then
  root_src="$(findmnt -no SOURCE /mnt)"
  esp_src="$(findmnt -no SOURCE /mnt/boot/efi 2>/dev/null || true)"
  if [ "$(parent_disk "$root_src" || true)" = "$DISK" ] && [ "$(attr "$root_src" LABEL)" = nixos ] &&
    [ -n "$esp_src" ] && [ "$(parent_disk "$esp_src" || true)" = "$DISK" ]; then
    warn "/mnt already holds a NixOS root on $DISK (from an earlier run of install.sh)"
    if ask "Reuse it (skip partitioning; nixos-install continues where it stopped)?" y; then
      REUSE=1
    else
      umount -R /mnt
    fi
  else
    die "/mnt is mounted from $root_src, which is not this script's root on $DISK: unmount it first (umount -R /mnt)"
  fi
fi

# ----------------------------------------------------------------------------- partition

if [ "$REUSE" = 0 ]; then
  info "What is on $DISK now"
  lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL "$DISK" | sed 's/^/    /'

  # look inside (read-only) for anything that is not an earlier NixOS install
  foreign=""
  probe="$(mktemp -d)"
  trap 'umount "$probe" 2>/dev/null; rmdir "$probe" 2>/dev/null' EXIT
  while read -r p fstype; do
    [ "$p" = "$DISK" ] && continue
    case "$fstype" in
    "" | swap) ;;
    vfat)
      if mount -o ro "$p" "$probe" 2>/dev/null; then
        for e in "$probe"/EFI/* "$probe"/efi/*; do
          [ -d "$e" ] || continue
          case "${e##*/}" in [Nn][Ii][Xx][Oo][Ss]* | [Bb][Oo][Oo][Tt]) ;; *) foreign="$foreign\n    $p: EFI/${e##*/}" ;; esac
        done
        umount "$probe"
      else
        foreign="$foreign\n    $p: vfat (could not inspect)"
      fi
      ;;
    ext4 | ext3 | ext2 | btrfs | xfs)
      opts=ro
      [ "$fstype" = xfs ] && opts=ro,norecovery
      [[ "$fstype" == ext* ]] && opts=ro,noload
      if mount -t "$fstype" -o "$opts" "$p" "$probe" 2>/dev/null; then
        osr=""
        for f in etc/os-release usr/lib/os-release @/etc/os-release @/usr/lib/os-release; do
          # an absolute symlink (NixOS: /etc/static/...) would point into the live system
          [ -f "$probe/$f" ] && [[ "$(readlink "$probe/$f")" != /* ]] && osr="$probe/$f" && break
        done
        if [ -e "$probe/etc/NIXOS" ] || [ -e "$probe/@/etc/NIXOS" ]; then
          : # an earlier NixOS install
        elif [ -n "$osr" ]; then
          id="$(sed -n 's/^ID=//p' "$osr" | tr -d '"')"
          name="$(sed -n 's/^PRETTY_NAME=//p' "$osr" | tr -d '"')"
          [ "$id" = nixos ] || foreign="$foreign\n    $p: ${name:-$id} installed"
        elif [ -n "$(find "$probe" -mindepth 1 -maxdepth 1 ! -name lost+found ! -name nix ! -name boot -print -quit)" ]; then
          foreign="$foreign\n    $p: $fstype with data on it"
        fi
        umount "$probe"
      else
        foreign="$foreign\n    $p: $fstype (could not inspect)"
      fi
      ;;
    *) foreign="$foreign\n    $p: $fstype" ;;
    esac
  done < <(lsblk -lnpo NAME,FSTYPE "$DISK")
  rmdir "$probe"
  trap - EXIT

  echo
  if [ -n "$foreign" ]; then
    warn "$DISK holds something other than an earlier NixOS install:"
    printf '%b\n' "$foreign"
    confirm="${DISK_SERIAL:-${DISK##*/}}"
    echo "  Everything on $DISK_NAME will be erased."
    read -r -p "  Type the disk's serial number ($confirm) to erase it anyway: " answer || die "no input"
  else
    confirm="ERASE"
    echo "  Everything on $DISK_NAME will be erased (only an earlier NixOS install or nothing found on it)."
    read -r -p "  Type ERASE to continue: " answer || die "no input"
  fi
  [ "$answer" = "$confirm" ] || die "not confirmed; nothing was changed"

  # last check right before writing: still the same, still eligible
  [ "$(attr "$DISK" SERIAL)" = "$DISK_SERIAL" ] || die "$DISK changed under us; nothing was changed"
  why="$(refusal "$DISK")"
  [ -z "$why" ] || die "refusing to install onto $DISK: $why"
  is_protected "$DISK" && die "refusing to install onto a protected disk"

  disk_mib=$(($(lsblk -bdno SIZE "$DISK") / 1024 / 1024))
  esp_end=$((1 + ESP_MIB))
  swap_end=$((esp_end + SWAP_GIB * 1024))
  [ $(((disk_mib - swap_end) / 1024)) -ge "$MIN_ROOT_GIB" ] || die "$DISK is too small for a ${MIN_ROOT_GIB} GiB root plus ${SWAP_GIB} GiB swap"

  info "Partitioning $DISK"
  umount -R /mnt 2>/dev/null || true
  for p in $(lsblk -lnpo NAME "$DISK" | tail -n +2); do
    swapoff "$p" 2>/dev/null || true
    wipefs -aq "$p" || true
  done
  wipefs -aq "$DISK"
  if [ "$SWAP_GIB" -gt 0 ]; then
    parted -s -a optimal "$DISK" -- mklabel gpt \
      mkpart NIXBOOT fat32 1MiB "${esp_end}MiB" set 1 esp on \
      mkpart nixos-swap linux-swap "${esp_end}MiB" "${swap_end}MiB" \
      mkpart nixos ext4 "${swap_end}MiB" 100%
    ESP_PART="$(part_dev "$DISK" 1)" SWAP_PART="$(part_dev "$DISK" 2)" ROOT_PART="$(part_dev "$DISK" 3)"
  else
    parted -s -a optimal "$DISK" -- mklabel gpt \
      mkpart NIXBOOT fat32 1MiB "${esp_end}MiB" set 1 esp on \
      mkpart nixos ext4 "${esp_end}MiB" 100%
    ESP_PART="$(part_dev "$DISK" 1)" SWAP_PART="" ROOT_PART="$(part_dev "$DISK" 2)"
  fi
  udevadm settle
  for p in "$ESP_PART" "$ROOT_PART" ${SWAP_PART:+"$SWAP_PART"}; do
    for _ in 1 2 3 4 5 6 7 8 9 10; do [ -b "$p" ] && break; sleep 1; done
    [ -b "$p" ] && [ "$(parent_disk "$p")" = "$DISK" ] || die "partition $p did not appear on $DISK"
  done
  ok "GPT: $ESP_PART EFI ${ESP_MIB} MiB${SWAP_PART:+, $SWAP_PART swap ${SWAP_GIB} GiB}, $ROOT_PART root"

  mkfs.fat -F 32 -n NIXBOOT "$ESP_PART" >/dev/null
  [ -z "$SWAP_PART" ] || mkswap -L nixos-swap "$SWAP_PART" >/dev/null
  mkfs.ext4 -q -F -L nixos "$ROOT_PART"
  ok "formatted"

  mount "$ROOT_PART" /mnt
  mkdir -p /mnt/boot/efi
  mount -o umask=0077 "$ESP_PART" /mnt/boot/efi
  [ -z "$SWAP_PART" ] || swapon "$SWAP_PART"
  ok "mounted at /mnt"
else
  ROOT_PART="$(findmnt -no SOURCE /mnt)"
  ESP_PART="$(findmnt -no SOURCE /mnt/boot/efi)"
  SWAP_PART="$(lsblk -lnpo NAME,LABEL "$DISK" | awk '$2 == "nixos-swap" { print $1 }')"
  if [ -n "$SWAP_PART" ] && ! swapon --noheadings --show=NAME | grep -qx "$SWAP_PART"; then swapon "$SWAP_PART"; fi
  ok "reusing $ROOT_PART (root) and $ESP_PART (EFI) at /mnt"
fi

# ----------------------------------------------------------------------------- hardware configuration

info "Hardware configuration"
# nixos-generate-config records every swap that is active and everything mounted under /mnt: make sure
# that is only the target disk, so the new system never mounts or swaps onto another disk
while read -r s; do
  [ -n "$s" ] || continue
  [ "$(parent_disk "$s" || true)" = "$DISK" ] && continue
  [[ "$s" == /dev/zram* ]] && continue
  warn "turning off swap on $s for the install (it is not on $DISK)"
  swapoff "$s"
done < <(swapon --noheadings --show=NAME)
while read -r src tgt; do
  [ "$(parent_disk "$src" || true)" = "$DISK" ] || die "$tgt is mounted from $src, which is not on $DISK: unmount it"
done < <(findmnt -rno SOURCE,TARGET | awk '$2 == "/mnt" || $2 ~ /^\/mnt\//')

HW_TMP="$(mktemp)"
trap 'rm -f "$HW_TMP"' EXIT
{
  echo "# Generated by install.sh on $(date +%F) for $DISK_NAME:"
  echo "#   nixos-generate-config --root /mnt --show-hardware-config"
  echo "# Regenerate it if the disk is repartitioned (UUIDs change). Do not edit; put settings in configuration.nix."
  nixos-generate-config --root /mnt --show-hardware-config 2>/dev/null
} >"$HW_TMP" || die "nixos-generate-config failed"

# every device the generated file references must be a partition of the target disk
mapfile -t refs < <(grep -oE '"/dev/[^"]+"' "$HW_TMP" | tr -d '"' | sort -u)
[ "${#refs[@]}" -gt 0 ] || die "the generated hardware configuration references no disks"
for r in "${refs[@]}"; do
  real="$(readlink -f "$r")"
  [ -b "$real" ] && [ "$(parent_disk "$real" || true)" = "$DISK" ] ||
    die "the generated hardware configuration references $r ($real), which is not on $DISK; stopping"
  ok "$r -> $real"
done
grep -q 'fileSystems."/"' "$HW_TMP" && grep -q 'fileSystems."/boot/efi"' "$HW_TMP" ||
  die "the generated hardware configuration lacks / or /boot/efi"

# ----------------------------------------------------------------------------- repository

REPO="/mnt/home/$USERNAME/nixos-config"
info "Repository at ${REPO#/mnt}"
mkdir -p "/mnt/home/$USERNAME"
if [ -e "$REPO" ]; then
  # only ever a copy made by an earlier run of this script onto the freshly formatted disk
  rm -rf "$REPO"
fi
cp -a "$SOURCE" "$REPO"
rm -f "$REPO"/result "$REPO"/result-*
chown -R 0:0 "$REPO" # root's until the user exists; handed over after nixos-install
cp "$HW_TMP" "$REPO/host/hardware-configuration.nix"
cat >"$REPO/vars.nix" <<EOF
# Machine-specific names, written by install.sh on $(date +%F). Edit by hand if they change.
{
  username = "$USERNAME";
  hostname = "$HOST";
}
EOF
if [ -d "$REPO/.git" ]; then
  # flakes only see files known to git; both files above are tracked, this catches anything new
  if command -v git >/dev/null; then
    git -c safe.directory='*' -C "$REPO" add -A
  else
    nix shell nixpkgs#git -c git -c safe.directory='*' -C "$REPO" add -A
  fi
else
  warn "$SOURCE is not a git clone; the flake is used as a plain directory"
fi
ok "copied, vars.nix and host/hardware-configuration.nix written"

# ----------------------------------------------------------------------------- install

cat <<EOF

  Hostname:   $HOST
  User:       $USERNAME (sudo through wheel; root has no password)
  Disk:       $DISK_NAME, mounted at /mnt
  Bootloader: GRUB on $ESP_PART (/boot/efi), UEFI entry "NixOS"
  Flake:      ${REPO#/mnt}#$HOST

EOF
if ! ask "Run nixos-install now? (downloads and builds the whole system; takes a while)" y; then
  cat <<EOF

Not installed. /mnt stays mounted; to finish by hand:
  sudo nixos-install --root /mnt --flake $REPO#$HOST --no-root-passwd --no-channel-copy
  sudo nixos-enter --root /mnt -- /nix/var/nix/profiles/system/sw/bin/passwd $USERNAME
  sudo nixos-enter --root /mnt -- /nix/var/nix/profiles/system/sw/bin/chown -R $USERNAME:users /home/$USERNAME
or simply run sudo ./install.sh again and reuse /mnt.
EOF
  exit 0
fi

info "UEFI boot entries before the install"
bash "$SOURCE/scripts/nixos-efi-entries" --esp "$ESP_PART" --label NixOS | sed 's/^/    /'

info "nixos-install"
nixos-install --root /mnt --flake "$REPO#$HOST" --no-root-passwd --no-channel-copy ||
  die "nixos-install failed; fix the error above and run sudo ./install.sh again (it offers to reuse /mnt)"
ok "system installed"

# ----------------------------------------------------------------------------- after the install

info "Finishing"
# password: chpasswd inside the new system (users.mutableUsers keeps it across rebuilds)
SW=/nix/var/nix/profiles/system/sw/bin # the installed system's tools (nixos-enter keeps the live PATH)
if printf '%s:%s\n' "$USERNAME" "$PASSWORD" | nixos-enter --root /mnt --silent -- "$SW/chpasswd" >/dev/null 2>&1; then
  ok "password set for $USERNAME"
else
  warn "setting the password failed; set it now"
  until nixos-enter --root /mnt --silent -- "$SW/passwd" "$USERNAME"; do warn "try again"; done
fi
unset PASSWORD

uid="$(awk -F: -v u="$USERNAME" '$1 == u { print $3 }' /mnt/etc/passwd)"
gid="$(awk -F: -v u="$USERNAME" '$1 == u { print $4 }' /mnt/etc/passwd)"
[ -n "$uid" ] || die "$USERNAME is missing from the installed /etc/passwd"
chown -R "$uid:$gid" "/mnt/home/$USERNAME"
chmod 700 "/mnt/home/$USERNAME"
ok "/home/$USERNAME and ~/nixos-config belong to $USERNAME"

missing=""
for g in $EXPECTED_GROUPS; do
  awk -F: -v g="$g" -v u="$USERNAME" '$1 == g { n = split($4, m, ","); for (i = 1; i <= n; i++) if (m[i] == u) f = 1 } END { exit !f }' \
    /mnt/etc/group || missing="$missing $g"
done
if [ -z "$missing" ]; then ok "groups: $EXPECTED_GROUPS"; else warn "$USERNAME is missing groups:$missing"; fi

# Wi-Fi networks saved on the live system (nmtui), so the first boot is online
nm_src=/etc/NetworkManager/system-connections
if compgen -G "$nm_src/*.nmconnection" >/dev/null; then
  mkdir -p "/mnt$nm_src"
  cp "$nm_src"/*.nmconnection "/mnt$nm_src/"
  chmod 600 "/mnt$nm_src"/*.nmconnection
  ok "copied the live system's network connections"
else
  warn "no saved NetworkManager connections on the live system; connect to Wi-Fi after the first login"
fi

# boot entries: exactly one "NixOS", pointing at the new ESP
esp_uuid="$(blkid -p -s PART_ENTRY_UUID -o value "$ESP_PART" | tr 'A-F' 'a-f')"
[ -f /mnt/boot/efi/EFI/NixOS/grubx64.efi ] && ok "GRUB installed at /boot/efi/EFI/NixOS/grubx64.efi" ||
  warn "/boot/efi/EFI/NixOS/grubx64.efi missing"
bash "$SOURCE/scripts/nixos-efi-entries" --esp "$ESP_PART" --label NixOS | sed 's/^/    /'
count="$(efibootmgr -v | grep -ciE "^Boot[0-9A-F]{4}\*?[[:space:]]+NixOS[[:space:]].*${esp_uuid}" || true)"
if [ "$count" = 1 ]; then
  ok "UEFI boot menu: one \"NixOS\" entry"
else
  warn "UEFI boot menu has $count \"NixOS\" entries for $ESP_PART:"
fi
efibootmgr | grep -E '^BootOrder|HD\(' | sed 's/^/    /'

cat <<EOF

${c_ok}Done.${c_off}

  After the reboot: the GRUB menu offers NixOS (and Artix Linux, chainloaded from its own disk). Log in as
  $USERNAME at the Noctalia greeter. The rest of the user setup (zinit, Neovim plugins, Mason tools, rustup,
  vibium, nix-index) runs in the background on the first boot once there is network:
      journalctl -fu nixos-first-boot
  Ollama models download in the background too:   journalctl -fu ollama-model-loader
  Rebuild after changes:                          rebuild   (or nixos-update to also update the inputs)
  Claude Code: run /mcp once to sign in to the Expo server. Obsidian vault: copy it to ~/Obsidian/Personal.

EOF
if ask "Reboot now? (remove the USB stick when the screen goes dark)" y; then
  swapoff -a 2>/dev/null || true
  umount -R /mnt || true
  reboot
fi
echo "/mnt is still mounted. Reboot with: sudo umount -R /mnt && sudo reboot"
