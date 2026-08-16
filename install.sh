#!/bin/bash
set -Eeuo pipefail

# ============================================================
# VOID LINUX AUTOMATED XFCE INSTALLER
# ============================================================
#
# Architecture: x86_64
# libc:         glibc
# Boot:         UEFI
# Partition:    GPT
# Desktop:      XFCE
# Display Mgr:  LightDM
# Network:      NetworkManager
#
# WARNING:
# THIS SCRIPT WILL COMPLETELY ERASE THE SELECTED DISK.
#
# ============================================================

export XBPS_ARCH="x86_64"

# ------------------------------------------------------------
# COLORS
# ------------------------------------------------------------

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_RED="\033[1;31m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_CYAN="\033[1;36m"
C_MAGENTA="\033[1;35m"

# ------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------

DISK=""
PART_EFI=""
PART_SWAP=""
PART_ROOT=""

SWAP_SIZE=""
USERNAME=""
USER_PASS=""
ROOT_PASS=""
HOSTNAME=""

REPO_URL=""

# ------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------

error_exit()
{
    echo
    echo -e "${C_RED}======================================================${C_RESET}"
    echo -e "${C_RED} ERROR: $1${C_RESET}"
    echo -e "${C_RED}======================================================${C_RESET}"
    echo
    exit 1
}

pause_step()
{
    echo
    echo -e "${C_YELLOW}--> Press [ENTER] to continue...${C_RESET}"
    read -r
}

cleanup_mounts()
{
    echo -e "${C_YELLOW}Cleaning up mounted filesystems...${C_RESET}"

    if [ -n "${PART_SWAP:-}" ]; then
        swapoff "$PART_SWAP" 2>/dev/null || true
    fi

    umount -R /mnt/boot/efi 2>/dev/null || true
    umount -R /mnt/dev 2>/dev/null || true
    umount -R /mnt/proc 2>/dev/null || true
    umount -R /mnt/sys 2>/dev/null || true
    umount -R /mnt/run 2>/dev/null || true
    umount -R /mnt 2>/dev/null || true
}

on_error()
{
    local exit_code=$?

    if [ "$exit_code" -ne 0 ]; then

        echo
        echo -e "${C_RED}======================================================${C_RESET}"
        echo -e "${C_RED} INSTALLATION FAILED${C_RESET}"
        echo -e "${C_RED} Cleaning up...${C_RESET}"
        echo -e "${C_RED}======================================================${C_RESET}"

        cleanup_mounts

        echo
        echo -e "${C_RED}Exit code: $exit_code${C_RESET}"
        echo
    fi
}

trap on_error ERR

# ------------------------------------------------------------
# ROOT CHECK
# ------------------------------------------------------------

clear

if [ "$(id -u)" -ne 0 ]; then
    error_exit "Please run this script as root."
fi

# ------------------------------------------------------------
# UEFI CHECK
# ------------------------------------------------------------

if [ ! -d /sys/firmware/efi ]; then
    error_exit "The live system was not booted in UEFI mode.

Reboot the Void Linux USB in UEFI mode and run this installer again."
fi

# ------------------------------------------------------------
# HEADER
# ------------------------------------------------------------

echo -e "${C_CYAN}======================================================${C_RESET}"
echo -e "${C_CYAN}${C_BOLD}       AUTOMATED VOID LINUX XFCE INSTALLER             ${C_RESET}"
echo -e "${C_CYAN}======================================================${C_RESET}"
echo
echo -e "${C_YELLOW}Architecture:${C_RESET} x86_64"
echo -e "${C_YELLOW}Libc:${C_RESET}         glibc"
echo -e "${C_YELLOW}Boot:${C_RESET}         UEFI"
echo -e "${C_YELLOW}Partition:${C_RESET}    GPT"
echo -e "${C_YELLOW}Desktop:${C_RESET}      XFCE"
echo -e "${C_YELLOW}Display:${C_RESET}      LightDM"
echo -e "${C_YELLOW}Network:${C_RESET}      NetworkManager"
echo

pause_step

# ============================================================
# NETWORK
# ============================================================

clear

echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo -e "${C_MAGENTA}${C_BOLD}             NETWORK & TIME CHECK                     ${C_RESET}"
echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo

echo -e "${C_YELLOW}Checking internet connection...${C_RESET}"

if ! ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
    error_exit "No internet connection detected."
fi

echo -e "${C_GREEN}Internet connection OK.${C_RESET}"

echo
echo -e "${C_YELLOW}Checking DNS...${C_RESET}"

if ! ping -c 1 -W 5 repo-de.voidlinux.org >/dev/null 2>&1; then

    echo -e "${C_YELLOW}DNS/repository test failed.${C_RESET}"

    if ! ping -c 1 -W 5 repo-fi.voidlinux.org >/dev/null 2>&1; then
        error_exit "DNS or internet connectivity is not working."
    fi
fi

echo -e "${C_GREEN}DNS OK.${C_RESET}"

# ------------------------------------------------------------
# TIME
# ------------------------------------------------------------

echo
echo -e "${C_YELLOW}Synchronizing system clock...${C_RESET}"

if command -v chronyd >/dev/null 2>&1; then
    chronyd -q 'server pool.ntp.org iburst' 2>/dev/null || true
elif command -v ntpd >/dev/null 2>&1; then
    ntpd -qg 2>/dev/null || true
fi

echo -e "${C_GREEN}Clock synchronization completed.${C_RESET}"

sleep 1

# ============================================================
# DRIVE SELECTION
# ============================================================

clear

echo -e "${C_CYAN}======================================================${C_RESET}"
echo -e "${C_CYAN}${C_BOLD}             STEP 1: SELECT TARGET DISK              ${C_RESET}"
echo -e "${C_CYAN}======================================================${C_RESET}"
echo

lsblk -o NAME,SIZE,TYPE,MODEL,MOUNTPOINTS

echo
echo -e "${C_YELLOW}------------------------------------------------------${C_RESET}"
echo

read -r -p "Enter target disk name (example: sda or nvme0n1): " DISK_NAME

DISK="/dev/${DISK_NAME}"

if [ ! -b "$DISK" ]; then
    error_exit "Device $DISK does not exist."
fi

# ------------------------------------------------------------
# DETECT LIVE USB
# ------------------------------------------------------------

LIVE_DRIVE=""

ROOT_SOURCE=$(findmnt -n -o SOURCE / 2>/dev/null || true)

if [ -n "$ROOT_SOURCE" ]; then
    LIVE_DRIVE=$(lsblk -no PKNAME "$ROOT_SOURCE" 2>/dev/null || true)
fi

if [ -n "$LIVE_DRIVE" ]; then

    echo
    echo -e "${C_RED}${C_BOLD}WARNING:${C_RESET}"
    echo -e "The live environment appears to be running from:"
    echo -e "${C_RED}/dev/${LIVE_DRIVE}${C_RESET}"
    echo

    if [ "$DISK_NAME" = "$LIVE_DRIVE" ]; then
        error_exit "You selected the disk containing the live USB."
    fi
fi

# ------------------------------------------------------------
# PARTITION NAMES
# ------------------------------------------------------------

if [[ "$DISK" == *"nvme"* ]] || [[ "$DISK" == *"mmcblk"* ]]; then

    PART_EFI="${DISK}p1"
    PART_SWAP="${DISK}p2"
    PART_ROOT="${DISK}p3"

else

    PART_EFI="${DISK}1"
    PART_SWAP="${DISK}2"
    PART_ROOT="${DISK}3"

fi

# ============================================================
# SYSTEM CONFIGURATION
# ============================================================

clear

echo -e "${C_CYAN}======================================================${C_RESET}"
echo -e "${C_CYAN}${C_BOLD}             STEP 2: SYSTEM CONFIGURATION             ${C_RESET}"
echo -e "${C_CYAN}======================================================${C_RESET}"
echo

read -r -p "Swap size in GB [4]: " SWAP_SIZE
SWAP_SIZE="${SWAP_SIZE:-4}"

if ! [[ "$SWAP_SIZE" =~ ^[0-9]+$ ]]; then
    error_exit "Swap size must be a whole number."
fi

read -r -p "Username: " USERNAME

if [ -z "$USERNAME" ]; then
    error_exit "Username cannot be empty."
fi

if ! [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    error_exit "Invalid username.

Use lowercase letters, numbers, '_' or '-'."
fi

read -r -s -p "Password for $USERNAME: " USER_PASS
echo

if [ -z "$USER_PASS" ]; then
    error_exit "User password cannot be empty."
fi

read -r -s -p "Root password: " ROOT_PASS
echo

if [ -z "$ROOT_PASS" ]; then
    error_exit "Root password cannot be empty."
fi

read -r -p "Hostname [voidlinux]: " HOSTNAME
HOSTNAME="${HOSTNAME:-voidlinux}"

# ============================================================
# REPOSITORY SELECTION
# ============================================================

clear

echo -e "${C_CYAN}======================================================${C_RESET}"
echo -e "${C_CYAN}${C_BOLD}             SELECT VOID LINUX MIRROR                 ${C_RESET}"
echo -e "${C_CYAN}======================================================${C_RESET}"
echo

echo -e "${C_GREEN}${C_BOLD}TIER 1 MIRRORS - RECOMMENDED${C_RESET}"
echo

echo "1) Germany - Frankfurt"
echo "   https://repo-de.voidlinux.org/current"
echo

echo "2) Finland - Helsinki"
echo "   https://repo-fi.voidlinux.org/current"
echo

echo "3) Fastly - Global CDN"
echo "   https://repo-fastly.voidlinux.org/current"
echo

echo "4) USA - Chicago"
echo "   https://mirrors.summithq.com/voidlinux/current"
echo

echo -e "${C_YELLOW}${C_BOLD}TIER 2 MIRRORS${C_RESET}"
echo

echo "5) Cloudflare CDN"
echo "   https://mirrors.cicku.me/voidlinux/current"
echo

echo "6) Denmark - Xemacs"
echo "   http://ftp.dk.xemacs.org/voidlinux/current"
echo

echo "7) Denmark - DotSRC"
echo "   https://mirrors.dotsrc.org/voidlinux/current"
echo

echo "8) Greece"
echo "   https://ftp.cc.uoc.gr/mirrors/linux/voidlinux/current"
echo

echo "9) Italy - GARR"
echo "   https://voidlinux.mirror.garr.it/current"
echo

echo "10) Poland"
echo "    https://void.sakamoto.pl/current"
echo

echo "11) Sweden - Lysator"
echo "    https://ftp.lysator.liu.se/pub/voidlinux/current"
echo

echo "12) Sweden - Accum"
echo "    https://mirror.accum.se/mirror/voidlinux/current"
echo

echo "13) Switzerland"
echo "    https://mirror.puzzle.ch/voidlinux/current"
echo

echo "14) USA - Virginia"
echo "    https://mirror.vofr.net/voidlinux/current"
echo

echo "15) USA - Michigan"
echo "    https://mirrors.lug.mtu.edu/voidlinux/current"
echo

echo "16) Australia"
echo "    https://mirror.aarnet.edu.au/pub/voidlinux/current"
echo

echo "17) Brazil - voidbr"
echo "    https://void.voidbr.org/voidlinux/current"
echo

echo "18) Brazil"
echo "    https://void.voidlinux.com.br/voidlinux/current"
echo

echo "19) Ecuador"
echo "    https://mirror.linux.ec/voidlinux/current"
echo

echo "20) Custom mirror"
echo

read -r -p "Select mirror [1-20] (default: 1): " REPO_CHOICE

case "$REPO_CHOICE" in

    1)
        REPO_URL="https://repo-de.voidlinux.org/current"
        ;;

    2)
        REPO_URL="https://repo-fi.voidlinux.org/current"
        ;;

    3)
        REPO_URL="https://repo-fastly.voidlinux.org/current"
        ;;

    4)
        REPO_URL="https://mirrors.summithq.com/voidlinux/current"
        ;;

    5)
        REPO_URL="https://mirrors.cicku.me/voidlinux/current"
        ;;

    6)
        REPO_URL="http://ftp.dk.xemacs.org/voidlinux/current"
        ;;

    7)
        REPO_URL="https://mirrors.dotsrc.org/voidlinux/current"
        ;;

    8)
        REPO_URL="https://ftp.cc.uoc.gr/mirrors/linux/voidlinux/current"
        ;;

    9)
        REPO_URL="https://voidlinux.mirror.garr.it/current"
        ;;

    10)
        REPO_URL="https://void.sakamoto.pl/current"
        ;;

    11)
        REPO_URL="https://ftp.lysator.liu.se/pub/voidlinux/current"
        ;;

    12)
        REPO_URL="https://mirror.accum.se/mirror/voidlinux/current"
        ;;

    13)
        REPO_URL="https://mirror.puzzle.ch/voidlinux/current"
        ;;

    14)
        REPO_URL="https://mirror.vofr.net/voidlinux/current"
        ;;

    15)
        REPO_URL="https://mirrors.lug.mtu.edu/voidlinux/current"
        ;;

    16)
        REPO_URL="https://mirror.aarnet.edu.au/pub/voidlinux/current"
        ;;

    17)
        REPO_URL="https://void.voidbr.org/voidlinux/current"
        ;;

    18)
        REPO_URL="https://void.voidlinux.com.br/voidlinux/current"
        ;;

    19)
        REPO_URL="https://mirror.linux.ec/voidlinux/current"
        ;;

    20)
        read -r -p "Enter custom repository URL: " REPO_URL

        if [ -z "$REPO_URL" ]; then
            REPO_URL="https://repo-de.voidlinux.org/current"
        fi
        ;;

    *)
        echo -e "${C_YELLOW}Invalid selection. Using Germany.${C_RESET}"
        REPO_URL="https://repo-de.voidlinux.org/current"
        ;;

esac

echo
echo -e "${C_GREEN}Selected repository:${C_RESET}"
echo -e "${C_BOLD}${REPO_URL}${C_RESET}"
echo

# ============================================================
# TEST REPOSITORY
# ============================================================

echo -e "${C_YELLOW}Testing repository connection...${C_RESET}"

REPO_TEST_URL="${REPO_URL}/x86_64-repodata"

if ! curl \
    -fsSL \
    --connect-timeout 10 \
    --max-time 30 \
    "$REPO_TEST_URL" \
    -o /tmp/void-repodata-test; then

    rm -f /tmp/void-repodata-test

    echo
    echo -e "${C_RED}Repository test FAILED.${C_RESET}"
    echo
    echo "The selected mirror cannot currently be reached."
    echo
    echo -e "${C_YELLOW}Try another mirror.${C_RESET}"

    exit 1
fi

rm -f /tmp/void-repodata-test

echo -e "${C_GREEN}Repository is reachable.${C_RESET}"

sleep 2

# ============================================================
# FINAL WARNING
# ============================================================

clear

echo -e "${C_RED}======================================================${C_RESET}"
echo -e "${C_RED}${C_BOLD}                  !!! WARNING !!!                    ${C_RESET}"
echo -e "${C_RED}======================================================${C_RESET}"
echo
echo -e "${C_RED}${C_BOLD}ALL DATA ON THIS DISK WILL BE PERMANENTLY ERASED.${C_RESET}"
echo

echo -e "${C_YELLOW}Target Disk:${C_RESET}   $DISK"
echo -e "${C_YELLOW}EFI:${C_RESET}           $PART_EFI  512 MB"
echo -e "${C_YELLOW}Swap:${C_RESET}          $PART_SWAP  ${SWAP_SIZE} GB"
echo -e "${C_YELLOW}Root:${C_RESET}          $PART_ROOT  Remaining"
echo
echo -e "${C_YELLOW}Username:${C_RESET}      $USERNAME"
echo -e "${C_YELLOW}Hostname:${C_RESET}      $HOSTNAME"
echo -e "${C_YELLOW}Repository:${C_RESET}    $REPO_URL"
echo

echo -e "${C_RED}======================================================${C_RESET}"

read -r -p "Type YES to erase $DISK and continue: " CONFIRM

if [ "$CONFIRM" != "YES" ]; then
    echo -e "${C_YELLOW}Installation cancelled.${C_RESET}"
    exit 0
fi

# ============================================================
# PARTITIONING
# ============================================================

clear

echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo -e "${C_MAGENTA}${C_BOLD}             [1/7] PARTITIONING DISK                  ${C_RESET}"
echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo

# Unmount anything under /mnt
umount -R /mnt 2>/dev/null || true

echo -e "${C_YELLOW}Wiping disk...${C_RESET}"

wipefs -af "$DISK"

echo -e "${C_YELLOW}Creating GPT partition table...${C_RESET}"

sfdisk --wipe always "$DISK" <<EOF
label: gpt
size=512M, type=U, name="EFI"
size=${SWAP_SIZE}G, type=S, name="SWAP"
size=+, type=L, name="ROOT"
EOF

partprobe "$DISK" 2>/dev/null || true
udevadm settle

sleep 2

# ------------------------------------------------------------
# WAIT FOR PARTITIONS
# ------------------------------------------------------------

for PART in "$PART_EFI" "$PART_SWAP" "$PART_ROOT"; do

    COUNT=0

    while [ ! -b "$PART" ]; do

        sleep 1

        COUNT=$((COUNT + 1))

        if [ "$COUNT" -ge 15 ]; then
            error_exit "Partition $PART was not detected."
        fi

    done

done

echo
echo -e "${C_GREEN}Partitions created successfully.${C_RESET}"
echo

lsblk "$DISK"

pause_step

# ============================================================
# FORMATTING
# ============================================================

clear

echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo -e "${C_MAGENTA}${C_BOLD}              [2/7] FORMATTING                       ${C_RESET}"
echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo

echo -e "${C_YELLOW}Formatting EFI...${C_RESET}"
mkfs.vfat -F32 "$PART_EFI"

echo -e "${C_YELLOW}Creating swap...${C_RESET}"
mkswap -f "$PART_SWAP"

echo -e "${C_YELLOW}Formatting root filesystem...${C_RESET}"
mkfs.ext4 -F "$PART_ROOT"

echo
echo -e "${C_GREEN}Formatting complete.${C_RESET}"

# ============================================================
# MOUNTING
# ============================================================

clear

echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo -e "${C_MAGENTA}${C_BOLD}              [3/7] MOUNTING                         ${C_RESET}"
echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo

mkdir -p /mnt

mount "$PART_ROOT" /mnt

mkdir -p /mnt/boot/efi

mount "$PART_EFI" /mnt/boot/efi

swapon "$PART_SWAP"

mkdir -p /mnt/etc

echo -e "${C_GREEN}Root mounted: /mnt${C_RESET}"
echo -e "${C_GREEN}EFI mounted:  /mnt/boot/efi${C_RESET}"
echo -e "${C_GREEN}Swap enabled.${C_RESET}"

# ------------------------------------------------------------
# DNS
# ------------------------------------------------------------

echo
echo -e "${C_YELLOW}Configuring DNS...${C_RESET}"

if [ -f /etc/resolv.conf ]; then
    cp -L /etc/resolv.conf /mnt/etc/resolv.conf 2>/dev/null || true
fi

if [ ! -s /mnt/etc/resolv.conf ]; then

    cat > /mnt/etc/resolv.conf <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

fi

# ============================================================
# XBPS KEYS
# ============================================================

echo
echo -e "${C_YELLOW}Preparing XBPS signing keys...${C_RESET}"

mkdir -p /mnt/var/db/xbps/keys

cp -a \
    /var/db/xbps/keys/. \
    /mnt/var/db/xbps/keys/

echo -e "${C_GREEN}XBPS keys copied.${C_RESET}"

# ============================================================
# VOID BASE SYSTEM
# ============================================================

clear

echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo -e "${C_MAGENTA}${C_BOLD}          [4/7] INSTALLING VOID BASE SYSTEM          ${C_RESET}"
echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo

echo -e "${C_YELLOW}Refreshing Void repository...${C_RESET}"

XBPS_ARCH=x86_64 xbps-install \
    -S \
    -r /mnt \
    -R "$REPO_URL"

echo
echo -e "${C_YELLOW}Installing base system and kernel...${C_RESET}"

XBPS_ARCH=x86_64 xbps-install \
    -y \
    -r /mnt \
    -R "$REPO_URL" \
    base-system \
    linux

echo
echo -e "${C_GREEN}Base system installed successfully.${C_RESET}"

# ============================================================
# VOID REPOSITORIES
# ============================================================

echo
echo -e "${C_YELLOW}Installing Void nonfree repository...${C_RESET}"

XBPS_ARCH=x86_64 xbps-install \
    -y \
    -r /mnt \
    -R "$REPO_URL" \
    void-repo-nonfree

# ============================================================
# DESKTOP PACKAGES
# ============================================================

echo
echo -e "${C_YELLOW}Installing XFCE and desktop packages...${C_RESET}"

XBPS_ARCH=x86_64 xbps-install \
    -y \
    -r /mnt \
    -R "$REPO_URL" \
    xfce4 \
    xfce4-pulseaudio-plugin \
    Thunar \
    lightdm \
    lightdm-gtk-greeter \
    NetworkManager \
    dbus \
    elogind \
    polkit \
    sudo \
    grub-x86_64-efi \
    efibootmgr \
    git \
    curl \
    wget \
    unzip \
    htop \
    jq \
    picom \
    plank \
    cava \
    font-roboto-ttf \
    jetbrains-mono

echo
echo -e "${C_GREEN}XFCE and desktop packages installed.${C_RESET}"

# ============================================================
# UPDATE
# ============================================================

echo
echo -e "${C_YELLOW}Updating installed packages...${C_RESET}"

XBPS_ARCH=x86_64 xbps-install \
    -y \
    -r /mnt \
    -u

# ============================================================
# FSTAB
# ============================================================

clear

echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo -e "${C_MAGENTA}${C_BOLD}              [5/7] CREATING FSTAB                   ${C_RESET}"
echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo

UUID_ROOT=$(blkid -s UUID -o value "$PART_ROOT")
UUID_EFI=$(blkid -s UUID -o value "$PART_EFI")
UUID_SWAP=$(blkid -s UUID -o value "$PART_SWAP")

if [ -z "$UUID_ROOT" ]; then
    error_exit "Could not determine root UUID."
fi

if [ -z "$UUID_EFI" ]; then
    error_exit "Could not determine EFI UUID."
fi

if [ -z "$UUID_SWAP" ]; then
    error_exit "Could not determine swap UUID."
fi

cat > /mnt/etc/fstab <<EOF
# Void Linux filesystem table

UUID=$UUID_ROOT / ext4 defaults,noatime 0 1
UUID=$UUID_EFI /boot/efi vfat defaults,noatime 0 2
UUID=$UUID_SWAP none swap sw 0 0
EOF

echo -e "${C_GREEN}/etc/fstab:${C_RESET}"
echo

cat /mnt/etc/fstab

# ============================================================
# CHROOT PREPARATION
# ============================================================

clear

echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo -e "${C_MAGENTA}${C_BOLD}              [6/7] SYSTEM CONFIGURATION              ${C_RESET}"
echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo

echo -e "${C_YELLOW}Configuring hostname...${C_RESET}"

echo "$HOSTNAME" > /mnt/etc/hostname

# ------------------------------------------------------------
# CHROOT MOUNTS
# ------------------------------------------------------------

echo -e "${C_YELLOW}Preparing chroot environment...${C_RESET}"

mount -t proc proc /mnt/proc

mount --rbind /sys /mnt/sys
mount --make-rslave /mnt/sys

mount --rbind /dev /mnt/dev
mount --make-rslave /mnt/dev

mount --rbind /run /mnt/run
mount --make-rslave /mnt/run

# ------------------------------------------------------------
# EXPORT VARIABLES
# ------------------------------------------------------------

export TARGET_USERNAME="$USERNAME"
export TARGET_USER_PASSWORD="$USER_PASS"
export TARGET_ROOT_PASSWORD="$ROOT_PASS"
export TARGET_HOSTNAME="$HOSTNAME"

# ============================================================
# CHROOT
# ============================================================

echo -e "${C_YELLOW}Entering Void Linux chroot...${C_RESET}"

chroot /mnt /bin/bash <<'CHROOT_EOF'

set -Eeuo pipefail

echo
echo "================================================"
echo " CONFIGURING VOID LINUX"
echo "================================================"
echo

# ------------------------------------------------------------
# HOSTNAME
# ------------------------------------------------------------

echo "$TARGET_HOSTNAME" > /etc/hostname

# ------------------------------------------------------------
# ROOT PASSWORD
# ------------------------------------------------------------

echo "root:$TARGET_ROOT_PASSWORD" | chpasswd

# ------------------------------------------------------------
# CREATE USER
# ------------------------------------------------------------

if ! id "$TARGET_USERNAME" >/dev/null 2>&1; then

    useradd \
        -m \
        -G wheel,audio,video,input,storage \
        -s /bin/bash \
        "$TARGET_USERNAME"

fi

echo "$TARGET_USERNAME:$TARGET_USER_PASSWORD" | chpasswd

# ------------------------------------------------------------
# SUDO
# ------------------------------------------------------------

mkdir -p /etc/sudoers.d

cat > /etc/sudoers.d/10-wheel <<EOF
%wheel ALL=(ALL:ALL) ALL
EOF

chmod 0440 /etc/sudoers.d/10-wheel

# ------------------------------------------------------------
# LOCALE
# ------------------------------------------------------------

if [ -f /etc/default/libc-locales ]; then

    sed -i \
        's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' \
        /etc/default/libc-locales

fi

echo "LANG=en_US.UTF-8" > /etc/locale.conf

# ------------------------------------------------------------
# SERVICES
# ------------------------------------------------------------

mkdir -p /var/service

if [ -d /etc/sv/dbus ]; then
    ln -sf /etc/sv/dbus /var/service/dbus
fi

if [ -d /etc/sv/elogind ]; then
    ln -sf /etc/sv/elogind /var/service/elogind
fi

if [ -d /etc/sv/NetworkManager ]; then
    ln -sf /etc/sv/NetworkManager /var/service/NetworkManager
fi

if [ -d /etc/sv/lightdm ]; then
    ln -sf /etc/sv/lightdm /var/service/lightdm
fi

# ------------------------------------------------------------
# XFCE DIRECTORIES
# ------------------------------------------------------------

USER_HOME="/home/$TARGET_USERNAME"

mkdir -p "$USER_HOME/.config"
mkdir -p "$USER_HOME/.themes"
mkdir -p "$USER_HOME/.icons"

# ------------------------------------------------------------
# XFCE DOTFILES
# ------------------------------------------------------------

echo
echo "Installing XFCE dotfiles..."

TEMP_DOTS="$USER_HOME/dotties_temp"

rm -rf "$TEMP_DOTS"

if git clone \
    --depth 1 \
    https://github.com/mehedirm6244/My_XFCE_dotties.git \
    "$TEMP_DOTS"; then

    SRC_DIR="$TEMP_DOTS"

    if [ -d "$TEMP_DOTS/Dotfiles" ]; then
        SRC_DIR="$TEMP_DOTS/Dotfiles"
    fi

    if [ -d "$SRC_DIR/.config" ]; then
        cp -a "$SRC_DIR/.config/." "$USER_HOME/.config/"
    fi

    if [ -d "$SRC_DIR/.themes" ]; then
        cp -a "$SRC_DIR/.themes/." "$USER_HOME/.themes/"
    fi

    if [ -d "$SRC_DIR/.icons" ]; then
        cp -a "$SRC_DIR/.icons/." "$USER_HOME/.icons/"
    fi

    rm -rf "$TEMP_DOTS"

    echo "XFCE dotfiles installed."

else

    echo "WARNING: Could not download XFCE dotfiles."
    echo "Continuing without dotfiles."

fi

# ------------------------------------------------------------
# OWNERSHIP
# ------------------------------------------------------------

chown -R \
    "$TARGET_USERNAME:$TARGET_USERNAME" \
    "$USER_HOME"

# ------------------------------------------------------------
# GRUB
# ------------------------------------------------------------

echo
echo "Installing GRUB..."

grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id="Void"

# ------------------------------------------------------------
# GRUB CONFIG
# ------------------------------------------------------------

echo
echo "Generating GRUB configuration..."

grub-mkconfig \
    -o /boot/grub/grub.cfg

# ------------------------------------------------------------
# FINAL XBPS CONFIGURATION
# ------------------------------------------------------------

echo
echo "Running xbps-reconfigure..."

xbps-reconfigure -fa

echo
echo "================================================"
echo " CHROOT CONFIGURATION COMPLETE"
echo "================================================"

CHROOT_EOF

# ============================================================
# REMOVE PASSWORD VARIABLES
# ============================================================

unset TARGET_USERNAME
unset TARGET_USER_PASSWORD
unset TARGET_ROOT_PASSWORD
unset TARGET_HOSTNAME

# ============================================================
# FINALIZE
# ============================================================

clear

echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo -e "${C_MAGENTA}${C_BOLD}              [7/7] FINALIZING                       ${C_RESET}"
echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo

echo -e "${C_YELLOW}Synchronizing filesystem...${C_RESET}"

sync

echo -e "${C_YELLOW}Disabling swap...${C_RESET}"

swapoff "$PART_SWAP" 2>/dev/null || true

echo -e "${C_YELLOW}Unmounting filesystems...${C_RESET}"

umount -R /mnt/boot/efi 2>/dev/null || true
umount -R /mnt/dev 2>/dev/null || true
umount -R /mnt/proc 2>/dev/null || true
umount -R /mnt/sys 2>/dev/null || true
umount -R /mnt/run 2>/dev/null || true
umount -R /mnt 2>/dev/null || true

sync

# ============================================================
# SUCCESS
# ============================================================

trap - ERR

clear

echo
echo -e "${C_GREEN}======================================================${C_RESET}"
echo -e "${C_GREEN}${C_BOLD}        VOID LINUX INSTALLATION COMPLETE              ${C_RESET}"
echo -e "${C_GREEN}======================================================${C_RESET}"
echo
echo -e "${C_GREEN}Disk:${C_RESET}       $DISK"
echo -e "${C_GREEN}EFI:${C_RESET}        $PART_EFI"
echo -e "${C_GREEN}Swap:${C_RESET}       $PART_SWAP"
echo -e "${C_GREEN}Root:${C_RESET}       $PART_ROOT"
echo -e "${C_GREEN}Hostname:${C_RESET}   $HOSTNAME"
echo -e "${C_GREEN}Username:${C_RESET}   $USERNAME"
echo -e "${C_GREEN}Mirror:${C_RESET}     $REPO_URL"
echo
echo -e "${C_GREEN}XFCE installed.${C_RESET}"
echo -e "${C_GREEN}LightDM installed.${C_RESET}"
echo -e "${C_GREEN}NetworkManager installed.${C_RESET}"
echo -e "${C_GREEN}GRUB installed.${C_RESET}"
echo -e "${C_GREEN}XFCE dotfiles installed when available.${C_RESET}"
echo
echo -e "${C_YELLOW}${C_BOLD}Remove the USB drive and reboot.${C_RESET}"
echo
echo -e "${C_CYAN}======================================================${C_RESET}"
echo
