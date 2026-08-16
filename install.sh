#!/bin/bash

set -Eeuo pipefail

# ============================================================
# VOID LINUX + XFCE AUTOMATED INSTALLER
# ============================================================
#
# Architecture : x86_64
# Init         : runit
# Desktop      : XFCE
# Display      : LightDM
# Boot         : UEFI / GPT
#
# WARNING:
# THIS SCRIPT WILL ERASE THE SELECTED DISK.
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
AUTO_MIRROR="false"

# ------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------

pause_step() {
    echo
    echo -e "${C_YELLOW}--> Press [ENTER] to continue...${C_RESET}"
    read -r
}

error_exit() {
    echo
    echo -e "${C_RED}======================================================${C_RESET}"
    echo -e "${C_RED}${C_BOLD} ERROR: $1${C_RESET}"
    echo -e "${C_RED}======================================================${C_RESET}"
    echo
    exit 1
}

safe_umount() {
    swapoff -a 2>/dev/null || true

    umount -R /mnt/dev 2>/dev/null || true
    umount -R /mnt/proc 2>/dev/null || true
    umount -R /mnt/sys 2>/dev/null || true
    umount -R /mnt/run 2>/dev/null || true
    umount -R /mnt 2>/dev/null || true
}

cleanup() {
    local exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        echo
        echo -e "${C_RED}======================================================${C_RESET}"
        echo -e "${C_RED} INSTALLATION FAILED - CLEANING UP                   ${C_RESET}"
        echo -e "${C_RED}======================================================${C_RESET}"

        safe_umount
    fi
}

trap cleanup EXIT

# ============================================================
# ROOT CHECK
# ============================================================

clear

if [ "$(id -u)" -ne 0 ]; then
    error_exit "Please run this script as root."
fi

# ============================================================
# UEFI CHECK
# ============================================================

if [ ! -d /sys/firmware/efi ]; then
    error_exit "This system is not booted in UEFI mode.

Reboot the Void Linux USB in UEFI mode."
fi

# ============================================================
# HEADER
# ============================================================

echo -e "${C_CYAN}======================================================${C_RESET}"
echo -e "${C_CYAN}${C_BOLD}   AUTOMATED VOID LINUX + CUSTOM XFCE RICE INSTALLER ${C_RESET}"
echo -e "${C_CYAN}======================================================${C_RESET}"
echo
echo -e "${C_YELLOW}Architecture:${C_RESET} x86_64"
echo -e "${C_YELLOW}Desktop:${C_RESET}      XFCE"
echo -e "${C_YELLOW}Display Manager:${C_RESET} LightDM"
echo -e "${C_YELLOW}Boot:${C_RESET}         UEFI"
echo -e "${C_YELLOW}Partition:${C_RESET}    GPT"
echo

pause_step

# ============================================================
# NETWORK CHECK
# ============================================================

clear

echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo -e "${C_MAGENTA}${C_BOLD}        NETWORK CONNECTIVITY CHECK                    ${C_RESET}"
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
    if ! ping -c 1 -W 5 repo-fi.voidlinux.org >/dev/null 2>&1; then
        error_exit "DNS is not working."
    fi
fi

echo -e "${C_GREEN}DNS OK.${C_RESET}"

# ------------------------------------------------------------
# TIME
# ------------------------------------------------------------

echo
echo -e "${C_YELLOW}Synchronizing system time...${C_RESET}"

if command -v chronyd >/dev/null 2>&1; then
    chronyd -q 'server pool.ntp.org iburst' 2>/dev/null || true
elif command -v ntpd >/dev/null 2>&1; then
    ntpd -qg 2>/dev/null || true
fi

echo -e "${C_GREEN}Time synchronization completed.${C_RESET}"

# ============================================================
# DRIVE SELECTION
# ============================================================

clear

echo -e "${C_CYAN}======================================================${C_RESET}"
echo -e "${C_CYAN}${C_BOLD}         STEP 1: SELECT TARGET STORAGE DRIVE          ${C_RESET}"
echo -e "${C_CYAN}======================================================${C_RESET}"
echo

lsblk -o NAME,SIZE,TYPE,MODEL,MOUNTPOINTS

echo
echo -e "${C_YELLOW}------------------------------------------------------${C_RESET}"

read -r -p "Enter target disk name (example: sda or nvme0n1): " DISK_NAME

if [ -z "$DISK_NAME" ]; then
    error_exit "No disk selected."
fi

DISK="/dev/$DISK_NAME"

if [ ! -b "$DISK" ]; then
    error_exit "Device $DISK does not exist."
fi

# ------------------------------------------------------------
# PREVENT LIVE USB SELECTION
# ------------------------------------------------------------

ROOT_SOURCE=$(findmnt -n -o SOURCE / 2>/dev/null || true)

if [ -n "$ROOT_SOURCE" ]; then

    LIVE_DRIVE=$(lsblk -no PKNAME "$ROOT_SOURCE" 2>/dev/null || true)

    if [ -n "$LIVE_DRIVE" ] && [ "$DISK_NAME" = "$LIVE_DRIVE" ]; then
        error_exit "You selected the disk containing the live environment."
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
echo -e "${C_CYAN}${C_BOLD}             SYSTEM CONFIGURATION                    ${C_RESET}"
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
    error_exit "Invalid username."
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
# REPOSITORIES
# ============================================================

TIER1_REPOS=(
    "https://repo-de.voidlinux.org/current"
    "https://repo-fi.voidlinux.org/current"
    "https://repo-fastly.voidlinux.org/current"
    "https://mirrors.summithq.com/voidlinux/current"
)

TIER2_REPOS=(
    "https://mirrors.cicku.me/voidlinux/current"
    "http://ftp.dk.xemacs.org/voidlinux/current"
    "https://mirrors.dotsrc.org/voidlinux/current"
    "https://ftp.cc.uoc.gr/mirrors/linux/voidlinux/current"
    "https://voidlinux.mirror.garr.it/current"
    "https://void.sakamoto.pl/current"
    "https://ftp.lysator.liu.se/pub/voidlinux/current"
    "https://mirror.accum.se/mirror/voidlinux/current"
    "https://mirror.puzzle.ch/voidlinux/current"
    "https://mirror.vofr.net/voidlinux/current"
    "https://mirrors.lug.mtu.edu/voidlinux/current"
    "https://mirror.aarnet.edu.au/pub/voidlinux/current"
    "https://void.voidbr.org/voidlinux/current"
    "https://void.voidlinux.com.br/voidlinux/current"
    "https://mirror.linux.ec/voidlinux/current"
)

# ============================================================
# MIRROR MENU
# ============================================================

clear

echo -e "${C_CYAN}======================================================${C_RESET}"
echo -e "${C_CYAN}${C_BOLD}        SELECT VOID LINUX REPOSITORY MIRROR           ${C_RESET}"
echo -e "${C_CYAN}======================================================${C_RESET}"
echo

echo -e "${C_GREEN}${C_BOLD}TIER 1 - RECOMMENDED${C_RESET}"
echo
echo "1) Germany - Frankfurt"
echo "   ${TIER1_REPOS[0]}"
echo
echo "2) Finland - Helsinki"
echo "   ${TIER1_REPOS[1]}"
echo
echo "3) Fastly - Global CDN"
echo "   ${TIER1_REPOS[2]}"
echo
echo "4) USA - Chicago"
echo "   ${TIER1_REPOS[3]}"
echo

echo -e "${C_YELLOW}${C_BOLD}TIER 2${C_RESET}"
echo

echo "5) Cloudflare Global CDN"
echo "   ${TIER2_REPOS[0]}"
echo
echo "6) Denmark - Xemacs"
echo "   ${TIER2_REPOS[1]}"
echo
echo "7) Denmark - DotSRC"
echo "   ${TIER2_REPOS[2]}"
echo
echo "8) Greece"
echo "   ${TIER2_REPOS[3]}"
echo
echo "9) Italy - GARR"
echo "   ${TIER2_REPOS[4]}"
echo
echo "10) Poland"
echo "    ${TIER2_REPOS[5]}"
echo
echo "11) Sweden - Lysator"
echo "    ${TIER2_REPOS[6]}"
echo
echo "12) Sweden - Accum"
echo "    ${TIER2_REPOS[7]}"
echo
echo "13) Switzerland"
echo "    ${TIER2_REPOS[8]}"
echo
echo "14) USA - Virginia"
echo "    ${TIER2_REPOS[9]}"
echo
echo "15) USA - Michigan"
echo "    ${TIER2_REPOS[10]}"
echo
echo "16) Australia"
echo "    ${TIER2_REPOS[11]}"
echo
echo "17) Brazil - voidbr"
echo "    ${TIER2_REPOS[12]}"
echo
echo "18) Brazil"
echo "    ${TIER2_REPOS[13]}"
echo
echo "19) Ecuador"
echo "    ${TIER2_REPOS[14]}"
echo
echo "20) AUTOMATIC TIER 1 FAILOVER"
echo
echo "21) Custom Mirror"
echo

read -r -p "Select mirror [1-21] (default: 1): " REPO_CHOICE
REPO_CHOICE="${REPO_CHOICE:-1}"

case "$REPO_CHOICE" in

    1)  REPO_URL="${TIER1_REPOS[0]}" ;;
    2)  REPO_URL="${TIER1_REPOS[1]}" ;;
    3)  REPO_URL="${TIER1_REPOS[2]}" ;;
    4)  REPO_URL="${TIER1_REPOS[3]}" ;;

    5)  REPO_URL="${TIER2_REPOS[0]}" ;;
    6)  REPO_URL="${TIER2_REPOS[1]}" ;;
    7)  REPO_URL="${TIER2_REPOS[2]}" ;;
    8)  REPO_URL="${TIER2_REPOS[3]}" ;;
    9)  REPO_URL="${TIER2_REPOS[4]}" ;;
    10) REPO_URL="${TIER2_REPOS[5]}" ;;
    11) REPO_URL="${TIER2_REPOS[6]}" ;;
    12) REPO_URL="${TIER2_REPOS[7]}" ;;
    13) REPO_URL="${TIER2_REPOS[8]}" ;;
    14) REPO_URL="${TIER2_REPOS[9]}" ;;
    15) REPO_URL="${TIER2_REPOS[10]}" ;;
    16) REPO_URL="${TIER2_REPOS[11]}" ;;
    17) REPO_URL="${TIER2_REPOS[12]}" ;;
    18) REPO_URL="${TIER2_REPOS[13]}" ;;
    19) REPO_URL="${TIER2_REPOS[14]}" ;;

    20)
        AUTO_MIRROR="true"
        ;;

    21)
        read -r -p "Enter custom repository URL: " REPO_URL

        if [ -z "$REPO_URL" ]; then
            REPO_URL="${TIER1_REPOS[0]}"
        fi
        ;;

    *)
        REPO_URL="${TIER1_REPOS[0]}"
        ;;

esac

if [ "$AUTO_MIRROR" = "true" ]; then
    echo
    echo -e "${C_GREEN}Automatic Tier 1 failover selected.${C_RESET}"
else
    echo
    echo -e "${C_GREEN}Using repository:${C_RESET}"
    echo "$REPO_URL"
fi

pause_step

# ============================================================
# FINAL WARNING
# ============================================================

clear

echo -e "${C_RED}======================================================${C_RESET}"
echo -e "${C_RED}${C_BOLD}                    WARNING                           ${C_RESET}"
echo -e "${C_RED}======================================================${C_RESET}"
echo

echo -e "${C_RED}${C_BOLD}THIS WILL ERASE THE ENTIRE DISK:${C_RESET}"
echo
echo "Disk:     $DISK"
echo "EFI:      $PART_EFI"
echo "Swap:     $PART_SWAP"
echo "Root:     $PART_ROOT"
echo
echo "Username: $USERNAME"
echo "Hostname: $HOSTNAME"

if [ "$AUTO_MIRROR" = "true" ]; then
    echo "Mirror:   Automatic Tier 1 failover"
else
    echo "Mirror:   $REPO_URL"
fi

echo
echo -e "${C_RED}ALL DATA ON $DISK WILL BE DESTROYED.${C_RESET}"
echo

read -r -p "Type YES to continue: " CONFIRM

if [ "$CONFIRM" != "YES" ]; then
    echo
    echo -e "${C_YELLOW}Installation cancelled.${C_RESET}"
    exit 0
fi

# ============================================================
# PARTITIONING
# ============================================================

clear

echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo -e "${C_MAGENTA}${C_BOLD} [1/7] WIPING AND PARTITIONING DISK                   ${C_RESET}"
echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo

safe_umount

echo -e "${C_YELLOW}Wiping filesystem signatures...${C_RESET}"

wipefs -af "$DISK"

echo -e "${C_YELLOW}Creating GPT partition table...${C_RESET}"

sfdisk --wipe always "$DISK" <<EOF
label: gpt
size=512M, type=U, name="EFI"
size=${SWAP_SIZE}G, type=S, name="SWAP"
size=+, type=L, name="ROOT"
EOF

partprobe "$DISK" 2>/dev/null || true
blockdev --rereadpt "$DISK" 2>/dev/null || true
udevadm trigger --subsystem-match=block 2>/dev/null || true
udevadm settle 2>/dev/null || true

echo
echo -e "${C_YELLOW}Waiting for partitions...${C_RESET}"

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

lsblk "$DISK"

pause_step

# ============================================================
# FORMATTING
# ============================================================

clear

echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo -e "${C_MAGENTA}${C_BOLD} [2/7] FORMATTING PARTITIONS                         ${C_RESET}"
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
echo -e "${C_MAGENTA}${C_BOLD} [3/7] MOUNTING FILESYSTEMS                          ${C_RESET}"
echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo

mkdir -p /mnt

mount "$PART_ROOT" /mnt

mkdir -p /mnt/boot/efi
mkdir -p /mnt/etc
mkdir -p /mnt/var/db/xbps/keys

mount "$PART_EFI" /mnt/boot/efi

swapon "$PART_SWAP"

# ------------------------------------------------------------
# DNS
# ------------------------------------------------------------

if [ -f /etc/resolv.conf ]; then
    cp -L /etc/resolv.conf /mnt/etc/resolv.conf 2>/dev/null || true
fi

if [ ! -s /mnt/etc/resolv.conf ]; then
    cat > /mnt/etc/resolv.conf <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
fi

echo
echo -e "${C_GREEN}Root mounted: /mnt${C_RESET}"
echo -e "${C_GREEN}EFI mounted: /mnt/boot/efi${C_RESET}"
echo -e "${C_GREEN}Swap enabled.${C_RESET}"

# ============================================================
# XBPS KEYS
# ============================================================

echo
echo -e "${C_YELLOW}Copying XBPS signing keys...${C_RESET}"

if [ -d /var/db/xbps/keys ]; then

    cp -a \
        /var/db/xbps/keys/. \
        /mnt/var/db/xbps/keys/

else

    error_exit "XBPS signing key directory does not exist."

fi

echo -e "${C_GREEN}XBPS keys copied.${C_RESET}"

# ============================================================
# BASE SYSTEM INSTALLATION
# ============================================================

clear

echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo -e "${C_MAGENTA}${C_BOLD} [4/7] INSTALLING VOID BASE SYSTEM                    ${C_RESET}"
echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo

INSTALL_SUCCESS="false"

if [ "$AUTO_MIRROR" = "true" ]; then

    echo -e "${C_YELLOW}Automatic Tier 1 failover enabled.${C_RESET}"
    echo

    for MIRROR in "${TIER1_REPOS[@]}"; do

        echo -e "${C_CYAN}------------------------------------------------------${C_RESET}"
        echo -e "${C_CYAN}Trying:${C_RESET} $MIRROR"
        echo -e "${C_CYAN}------------------------------------------------------${C_RESET}"

        if XBPS_ARCH=x86_64 xbps-install \
            -S \
            -y \
            -r /mnt \
            -R "$MIRROR" \
            base-system \
            linux; then

            REPO_URL="$MIRROR"
            INSTALL_SUCCESS="true"

            echo
            echo -e "${C_GREEN}Mirror succeeded:${C_RESET} $MIRROR"
            break

        fi

        echo
        echo -e "${C_RED}Mirror failed. Trying next mirror...${C_RESET}"
        echo

    done

else

    echo -e "${C_YELLOW}Repository:${C_RESET} $REPO_URL"
    echo

    if XBPS_ARCH=x86_64 xbps-install \
        -S \
        -y \
        -r /mnt \
        -R "$REPO_URL" \
        base-system \
        linux; then

        INSTALL_SUCCESS="true"

    fi

fi

if [ "$INSTALL_SUCCESS" != "true" ]; then
    error_exit "XBPS could not install the Void base system."
fi

echo
echo -e "${C_GREEN}Void base system installed successfully.${C_RESET}"

# ============================================================
# REPOSITORY PACKAGES
# ============================================================

echo
echo -e "${C_YELLOW}Installing Void repository packages...${C_RESET}"

XBPS_ARCH=x86_64 xbps-install \
    -y \
    -r /mnt \
    -R "$REPO_URL" \
    void-repo-nonfree

# ============================================================
# DESKTOP / UTILITIES
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
    grub-x86_64-efi \
    efibootmgr \
    NetworkManager \
    dbus \
    elogind \
    polkit \
    sudo \
    git \
    curl \
    wget \
    picom \
    plank \
    cava \
    jq \
    htop \
    unzip \
    font-roboto-ttf \
    jetbrains-mono

echo
echo -e "${C_GREEN}XFCE and desktop packages installed.${C_RESET}"

# ============================================================
# FSTAB
# ============================================================

clear

echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo -e "${C_MAGENTA}${C_BOLD} [5/7] GENERATING /etc/fstab                       ${C_RESET}"
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

cat /mnt/etc/fstab

# ============================================================
# CHROOT MOUNTS
# ============================================================

clear

echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo -e "${C_MAGENTA}${C_BOLD} [6/7] CONFIGURING INSTALLED SYSTEM                  ${C_RESET}"
echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo

mount --rbind /dev /mnt/dev
mount --make-rslave /mnt/dev

mount --rbind /proc /mnt/proc
mount --make-rslave /mnt/proc

mount --rbind /sys /mnt/sys
mount --make-rslave /mnt/sys

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

chroot /mnt /bin/bash <<'CHROOT_EOF'

set -Eeuo pipefail

# ------------------------------------------------------------
# HOSTNAME
# ------------------------------------------------------------

echo "$TARGET_HOSTNAME" > /etc/hostname

# ------------------------------------------------------------
# ROOT PASSWORD
# ------------------------------------------------------------

echo "root:$TARGET_ROOT_PASSWORD" | chpasswd

# ------------------------------------------------------------
# USER
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

cat > /etc/sudoers.d/wheel <<EOF
%wheel ALL=(ALL:ALL) ALL
EOF

chmod 0440 /etc/sudoers.d/wheel

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
# XFCE DOTFILES
# ------------------------------------------------------------

USER_HOME="/home/$TARGET_USERNAME"

mkdir -p \
    "$USER_HOME/.config" \
    "$USER_HOME/.themes" \
    "$USER_HOME/.icons"

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

    echo "WARNING: XFCE dotfiles could not be downloaded."
    echo "Continuing installation."

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
# RECONFIGURE PACKAGES
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

unset USER_PASS
unset ROOT_PASS

# ============================================================
# FINALIZATION
# ============================================================

clear

echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo -e "${C_MAGENTA}${C_BOLD} [7/7] FINALIZING INSTALLATION                       ${C_RESET}"
echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo

sync

echo -e "${C_YELLOW}Disabling swap...${C_RESET}"

swapoff "$PART_SWAP" 2>/dev/null || true

echo -e "${C_YELLOW}Unmounting filesystems...${C_RESET}"

umount -R /mnt/run 2>/dev/null || true
umount -R /mnt/dev 2>/dev/null || true
umount -R /mnt/proc 2>/dev/null || true
umount -R /mnt/sys 2>/dev/null || true
umount -R /mnt 2>/dev/null || true

sync

# ============================================================
# SUCCESS
# ============================================================

trap - EXIT

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
echo -e "${C_GREEN}Username:${C_RESET}   $USERNAME"
echo -e "${C_GREEN}Hostname:${C_RESET}   $HOSTNAME"
echo -e "${C_GREEN}Repository:${C_RESET} $REPO_URL"
echo
echo -e "${C_GREEN}XFCE installed.${C_RESET}"
echo -e "${C_GREEN}LightDM installed.${C_RESET}"
echo -e "${C_GREEN}NetworkManager installed.${C_RESET}"
echo -e "${C_GREEN}GRUB installed.${C_RESET}"
echo
echo -e "${C_YELLOW}${C_BOLD}Remove the installation USB and reboot.${C_RESET}"
echo
