#!/bin/bash
set -Eeuo pipefail

# ============================================================
# VOID LINUX AUTOMATED XFCE INSTALLER
# x86_64 / glibc / UEFI / GPT
#
# WARNING:
# This script completely erases the selected target disk.
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

    swapoff "$PART_SWAP" 2>/dev/null || true

    if mountpoint -q /mnt/boot/efi 2>/dev/null; then
        umount -R /mnt/boot/efi 2>/dev/null || true
    fi

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
        echo -e "${C_RED}The installer stopped because an error occurred.${C_RESET}"
        echo -e "${C_YELLOW}Exit code: $exit_code${C_RESET}"
    fi
}

trap on_error ERR

# ------------------------------------------------------------
# ROOT CHECK
# ------------------------------------------------------------

clear

if [ "$(id -u)" -ne 0 ]; then
    error_exit "Run this script as root."
fi

# ------------------------------------------------------------
# UEFI CHECK
# ------------------------------------------------------------

if [ ! -d /sys/firmware/efi ]; then
    error_exit "This computer was not booted in UEFI mode.

Reboot the Void Linux USB in UEFI mode and run the script again."
fi

# ------------------------------------------------------------
# HEADER
# ------------------------------------------------------------

echo -e "${C_CYAN}======================================================${C_RESET}"
echo -e "${C_CYAN}${C_BOLD}       AUTOMATED VOID LINUX XFCE INSTALLER            ${C_RESET}"
echo -e "${C_CYAN}======================================================${C_RESET}"
echo
echo -e "${C_YELLOW}Target:${C_RESET} x86_64 / glibc / UEFI / GPT"
echo -e "${C_YELLOW}Desktop:${C_RESET} XFCE"
echo -e "${C_YELLOW}Bootloader:${C_RESET} GRUB"
echo

pause_step

# ------------------------------------------------------------
# NETWORK CHECK
# ------------------------------------------------------------

clear

echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo -e "${C_MAGENTA}${C_BOLD}             CHECKING INTERNET CONNECTION             ${C_RESET}"
echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo

if ! ping -c 1 -W 3 repo-default.voidlinux.org >/dev/null 2>&1; then

    if ! ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
        error_exit "No internet connection detected."
    fi
fi

echo -e "${C_GREEN}Internet connection OK.${C_RESET}"

# ------------------------------------------------------------
# TIME SYNCHRONIZATION
# ------------------------------------------------------------

echo
echo -e "${C_YELLOW}Synchronizing system clock...${C_RESET}"

if command -v chronyd >/dev/null 2>&1; then
    chronyd -q 'server pool.ntp.org iburst' 2>/dev/null || true
elif command -v ntpd >/dev/null 2>&1; then
    ntpd -qg 2>/dev/null || true
fi

echo -e "${C_GREEN}Clock synchronization attempted.${C_RESET}"

sleep 1

# ------------------------------------------------------------
# DRIVE SELECTION
# ------------------------------------------------------------

clear

echo -e "${C_CYAN}======================================================${C_RESET}"
echo -e "${C_CYAN}${C_BOLD}              STEP 1: SELECT TARGET DISK             ${C_RESET}"
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
    echo -e "The live system appears to be running from:"
    echo -e "${C_RED}/dev/${LIVE_DRIVE}${C_RESET}"
    echo

    if [ "$DISK_NAME" = "$LIVE_DRIVE" ]; then
        error_exit "You selected the disk containing the live system."
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

# ------------------------------------------------------------
# USER CONFIGURATION
# ------------------------------------------------------------

clear

echo -e "${C_CYAN}======================================================${C_RESET}"
echo -e "${C_CYAN}${C_BOLD}         STEP 2: SYSTEM CONFIGURATION                ${C_RESET}"
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

# ------------------------------------------------------------
# REPOSITORY SELECTION
# ------------------------------------------------------------

clear

echo -e "${C_CYAN}======================================================${C_RESET}"
echo -e "${C_CYAN}${C_BOLD}            SELECT VOID LINUX MIRROR                 ${C_RESET}"
echo -e "${C_CYAN}======================================================${C_RESET}"
echo

echo "1) Default / Global"
echo "2) Germany / Europe"
echo "3) USA / Kansas"
echo "4) Custom"
echo

read -r -p "Select mirror [1-4] (default: 1): " REPO_CHOICE

case "$REPO_CHOICE" in

    2)
        REPO_URL="https://alpha.de.repo.voidlinux.org/current"
        ;;

    3)
        REPO_URL="https://a.repo.voidlinux.org/current"
        ;;

    4)
        read -r -p "Enter repository URL: " REPO_URL

        if [ -z "$REPO_URL" ]; then
            REPO_URL="https://repo-default.voidlinux.org/current"
        fi
        ;;

    *)
        REPO_URL="https://repo-default.voidlinux.org/current"
        ;;

esac

echo
echo -e "${C_GREEN}Using repository:${C_RESET}"
echo "$REPO_URL"

sleep 2

# ------------------------------------------------------------
# FINAL WARNING
# ------------------------------------------------------------

clear

echo -e "${C_RED}======================================================${C_RESET}"
echo -e "${C_RED}${C_BOLD}                 !!! WARNING !!!                     ${C_RESET}"
echo -e "${C_RED}======================================================${C_RESET}"
echo
echo -e "${C_RED}${C_BOLD}ALL DATA ON THIS DISK WILL BE DESTROYED.${C_RESET}"
echo
echo -e "${C_YELLOW}Target disk:${C_RESET} $DISK"
echo
echo -e "${C_YELLOW}Partitions:${C_RESET}"
echo "  $PART_EFI  -> EFI     512 MB"
echo "  $PART_SWAP -> SWAP    ${SWAP_SIZE} GB"
echo "  $PART_ROOT -> ROOT    Remaining space"
echo
echo -e "${C_YELLOW}Username:${C_RESET} $USERNAME"
echo -e "${C_YELLOW}Repository:${C_RESET} $REPO_URL"
echo
echo -e "${C_RED}======================================================${C_RESET}"
echo

read -r -p "Type YES to completely erase $DISK: " CONFIRM

if [ "$CONFIRM" != "YES" ]; then
    echo -e "${C_YELLOW}Installation cancelled.${C_RESET}"
    exit 0
fi

# ------------------------------------------------------------
# UNMOUNT EXISTING TARGET
# ------------------------------------------------------------

echo
echo -e "${C_YELLOW}Unmounting existing filesystems...${C_RESET}"

umount -R /mnt 2>/dev/null || true

swapoff "$PART_SWAP" 2>/dev/null || true

# ------------------------------------------------------------
# PARTITION DISK
# ------------------------------------------------------------

clear

echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo -e "${C_MAGENTA}${C_BOLD}             [1/7] PARTITIONING DISK                 ${C_RESET}"
echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo

echo -e "${C_YELLOW}Wiping old filesystem signatures...${C_RESET}"

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
# CHECK PARTITIONS
# ------------------------------------------------------------

for PART in "$PART_EFI" "$PART_SWAP" "$PART_ROOT"; do

    COUNT=0

    while [ ! -b "$PART" ]; do

        sleep 1

        COUNT=$((COUNT + 1))

        if [ "$COUNT" -ge 10 ]; then
            error_exit "Partition $PART was not detected."
        fi

    done

done

echo
echo -e "${C_GREEN}Partitions created successfully.${C_RESET}"

lsblk "$DISK"

pause_step

# ------------------------------------------------------------
# FORMAT
# ------------------------------------------------------------

clear

echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo -e "${C_MAGENTA}${C_BOLD}             [2/7] FORMATTING DISK                   ${C_RESET}"
echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo

echo -e "${C_YELLOW}Formatting EFI partition...${C_RESET}"

mkfs.vfat -F32 "$PART_EFI"

echo -e "${C_YELLOW}Creating swap...${C_RESET}"

mkswap -f "$PART_SWAP"

echo -e "${C_YELLOW}Formatting root filesystem...${C_RESET}"

mkfs.ext4 -F "$PART_ROOT"

echo
echo -e "${C_GREEN}Formatting complete.${C_RESET}"

# ------------------------------------------------------------
# MOUNT
# ------------------------------------------------------------

clear

echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo -e "${C_MAGENTA}${C_BOLD}          [3/7] MOUNTING FILESYSTEMS                 ${C_RESET}"
echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo

mkdir -p /mnt

mount "$PART_ROOT" /mnt

mkdir -p /mnt/boot/efi

mount "$PART_EFI" /mnt/boot/efi

swapon "$PART_SWAP"

echo -e "${C_GREEN}Root mounted at /mnt.${C_RESET}"
echo -e "${C_GREEN}EFI mounted at /mnt/boot/efi.${C_RESET}"
echo -e "${C_GREEN}Swap enabled.${C_RESET}"

# ------------------------------------------------------------
# DNS
# ------------------------------------------------------------

echo
echo -e "${C_YELLOW}Configuring DNS...${C_RESET}"

if [ -f /etc/resolv.conf ]; then
    cp -L /etc/resolv.conf /mnt/etc/resolv.conf 2>/dev/null || true
fi

# Fallback DNS
if [ ! -s /mnt/etc/resolv.conf ]; then

    cat > /mnt/etc/resolv.conf <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

fi

# ------------------------------------------------------------
# COPY XBPS KEYS
# ------------------------------------------------------------

echo
echo -e "${C_YELLOW}Copying Void XBPS signing keys...${C_RESET}"

mkdir -p /mnt/var/db/xbps/keys

cp -a /var/db/xbps/keys/* /mnt/var/db/xbps/keys/

# ------------------------------------------------------------
# BOOTSTRAP VOID
# ------------------------------------------------------------

clear

echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo -e "${C_MAGENTA}${C_BOLD}       [4/7] INSTALLING VOID BASE SYSTEM             ${C_RESET}"
echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo

echo -e "${C_YELLOW}Installing base-system and kernel...${C_RESET}"

XBPS_ARCH=x86_64 xbps-install \
    -S \
    -r /mnt \
    -R "$REPO_URL" \
    base-system \
    linux

echo
echo -e "${C_GREEN}Void base system installed.${C_RESET}"

# ------------------------------------------------------------
# INSTALL REPOSITORIES
# ------------------------------------------------------------

echo
echo -e "${C_YELLOW}Installing repository definitions...${C_RESET}"

XBPS_ARCH=x86_64 xbps-install \
    -y \
    -r /mnt \
    -R "$REPO_URL" \
    void-repo-nonfree

# ------------------------------------------------------------
# INSTALL DESKTOP
# ------------------------------------------------------------

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
echo -e "${C_GREEN}Desktop packages installed.${C_RESET}"

# ------------------------------------------------------------
# UPDATE TARGET
# ------------------------------------------------------------

echo
echo -e "${C_YELLOW}Updating installed packages...${C_RESET}"

XBPS_ARCH=x86_64 xbps-install \
    -y \
    -r /mnt \
    -u

# ------------------------------------------------------------
# FSTAB
# ------------------------------------------------------------

clear

echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo -e "${C_MAGENTA}${C_BOLD}              [5/7] CREATING FSTAB                   ${C_RESET}"
echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo

UUID_ROOT=$(blkid -s UUID -o value "$PART_ROOT")
UUID_EFI=$(blkid -s UUID -o value "$PART_EFI")
UUID_SWAP=$(blkid -s UUID -o value "$PART_SWAP")

if [ -z "$UUID_ROOT" ] || [ -z "$UUID_EFI" ] || [ -z "$UUID_SWAP" ]; then
    error_exit "Could not determine partition UUIDs."
fi

cat > /mnt/etc/fstab <<EOF
# Void Linux filesystem table

UUID=$UUID_ROOT / ext4 defaults,noatime 0 1
UUID=$UUID_EFI /boot/efi vfat defaults,noatime 0 2
UUID=$UUID_SWAP none swap sw 0 0
EOF

echo -e "${C_GREEN}/etc/fstab created:${C_RESET}"
cat /mnt/etc/fstab

# ------------------------------------------------------------
# HOSTNAME
# ------------------------------------------------------------

echo
read -r -p "Hostname [voidlinux]: " HOSTNAME

HOSTNAME="${HOSTNAME:-voidlinux}"

echo "$HOSTNAME" > /mnt/etc/hostname

# ------------------------------------------------------------
# CHROOT MOUNTS
# ------------------------------------------------------------

clear

echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo -e "${C_MAGENTA}${C_BOLD}          [6/7] CONFIGURING VOID LINUX              ${C_RESET}"
echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo

echo -e "${C_YELLOW}Preparing chroot environment...${C_RESET}"

# /proc
mount -t proc proc /mnt/proc

# /sys
mount --rbind /sys /mnt/sys
mount --make-rslave /mnt/sys

# /dev
mount --rbind /dev /mnt/dev
mount --make-rslave /mnt/dev

# /run
mount --rbind /run /mnt/run
mount --make-rslave /mnt/run

# ------------------------------------------------------------
# PASS VARIABLES INTO CHROOT
# ------------------------------------------------------------

export TARGET_USERNAME="$USERNAME"
export TARGET_USER_PASSWORD="$USER_PASS"
export TARGET_ROOT_PASSWORD="$ROOT_PASS"
export TARGET_HOSTNAME="$HOSTNAME"

# ------------------------------------------------------------
# CHROOT CONFIGURATION
# ------------------------------------------------------------

echo -e "${C_YELLOW}Entering Void Linux chroot...${C_RESET}"

chroot /mnt /bin/bash <<'CHROOT_EOF'

set -Eeuo pipefail

echo
echo "=============================================="
echo " Configuring Void Linux"
echo "=============================================="
echo

# ----------------------------------------------------------
# HOSTNAME
# ----------------------------------------------------------

echo "$TARGET_HOSTNAME" > /etc/hostname

# ----------------------------------------------------------
# ROOT PASSWORD
# ----------------------------------------------------------

echo "root:$TARGET_ROOT_PASSWORD" | chpasswd

# ----------------------------------------------------------
# CREATE USER
# ----------------------------------------------------------

if ! id "$TARGET_USERNAME" >/dev/null 2>&1; then

    useradd \
        -m \
        -G wheel,audio,video,input,storage \
        -s /bin/bash \
        "$TARGET_USERNAME"

fi

echo "$TARGET_USERNAME:$TARGET_USER_PASSWORD" | chpasswd

# ----------------------------------------------------------
# SUDO
# ----------------------------------------------------------

mkdir -p /etc/sudoers.d

cat > /etc/sudoers.d/10-wheel <<EOF
%wheel ALL=(ALL:ALL) ALL
EOF

chmod 0440 /etc/sudoers.d/10-wheel

# ----------------------------------------------------------
# LOCALE
# ----------------------------------------------------------

if [ -f /etc/default/libc-locales ]; then

    sed -i \
        's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' \
        /etc/default/libc-locales

fi

echo "LANG=en_US.UTF-8" > /etc/locale.conf

# ----------------------------------------------------------
# SERVICES
# ----------------------------------------------------------

mkdir -p /var/service

# D-Bus
if [ -d /etc/sv/dbus ]; then
    ln -sf /etc/sv/dbus /var/service/dbus
fi

# elogind
if [ -d /etc/sv/elogind ]; then
    ln -sf /etc/sv/elogind /var/service/elogind
fi

# NetworkManager
if [ -d /etc/sv/NetworkManager ]; then
    ln -sf /etc/sv/NetworkManager /var/service/NetworkManager
fi

# LightDM
if [ -d /etc/sv/lightdm ]; then
    ln -sf /etc/sv/lightdm /var/service/lightdm
fi

# ----------------------------------------------------------
# XFCE USER DIRECTORIES
# ----------------------------------------------------------

USER_HOME="/home/$TARGET_USERNAME"

mkdir -p "$USER_HOME/.config"
mkdir -p "$USER_HOME/.themes"
mkdir -p "$USER_HOME/.icons"

# ----------------------------------------------------------
# INSTALL XFCE DOTFILES
# ----------------------------------------------------------

echo
echo "Installing XFCE dotfiles..."

if command -v git >/dev/null 2>&1; then

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
        echo "The installation will continue."

    fi

fi

# ----------------------------------------------------------
# OWNERSHIP
# ----------------------------------------------------------

chown -R \
    "$TARGET_USERNAME:$TARGET_USERNAME" \
    "$USER_HOME"

# ----------------------------------------------------------
# GRUB CONFIGURATION
# ----------------------------------------------------------

echo
echo "Installing GRUB..."

grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id="Void"

# ----------------------------------------------------------
# GRUB CONFIG
# ----------------------------------------------------------

grub-mkconfig -o /boot/grub/grub.cfg

# ----------------------------------------------------------
# LOCALE
# ----------------------------------------------------------

if command -v xbps-reconfigure >/dev/null 2>&1; then

    if [ -f /etc/default/libc-locales ]; then
        xbps-reconfigure -f glibc-locales || true
    fi

fi

# ----------------------------------------------------------
# FINAL PACKAGE CONFIGURATION
# ----------------------------------------------------------

echo
echo "Running xbps-reconfigure..."

xbps-reconfigure -fa

echo
echo "=============================================="
echo " Chroot configuration complete"
echo "=============================================="

CHROOT_EOF

# ------------------------------------------------------------
# REMOVE PASSWORD VARIABLES
# ------------------------------------------------------------

unset TARGET_USERNAME
unset TARGET_USER_PASSWORD
unset TARGET_ROOT_PASSWORD
unset TARGET_HOSTNAME

# ------------------------------------------------------------
# FINAL GRUB REBUILD
# ------------------------------------------------------------

echo
echo -e "${C_GREEN}Chroot configuration completed.${C_RESET}"

# ------------------------------------------------------------
# SYNC
# ------------------------------------------------------------

sync

# ------------------------------------------------------------
# UNMOUNT
# ------------------------------------------------------------

clear

echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo -e "${C_MAGENTA}${C_BOLD}             [7/7] FINALIZING INSTALL                ${C_RESET}"
echo -e "${C_MAGENTA}======================================================${C_RESET}"
echo

echo -e "${C_YELLOW}Synchronizing disk...${C_RESET}"

sync

echo -e "${C_YELLOW}Disabling swap...${C_RESET}"

swapoff "$PART_SWAP" 2>/dev/null || true

echo -e "${C_YELLOW}Unmounting filesystems...${C_RESET}"

umount -R /mnt 2>/dev/null || true

sync

# ------------------------------------------------------------
# SUCCESS
# ------------------------------------------------------------

trap - ERR

clear

echo
echo -e "${C_GREEN}======================================================${C_RESET}"
echo -e "${C_GREEN}${C_BOLD}          VOID LINUX INSTALLATION COMPLETE            ${C_RESET}"
echo -e "${C_GREEN}======================================================${C_RESET}"
echo
echo -e "${C_GREEN}Disk:${C_RESET}      $DISK"
echo -e "${C_GREEN}Root:${C_RESET}      $PART_ROOT"
echo -e "${C_GREEN}EFI:${C_RESET}       $PART_EFI"
echo -e "${C_GREEN}Swap:${C_RESET}      $PART_SWAP"
echo -e "${C_GREEN}Hostname:${C_RESET}  $HOSTNAME"
echo -e "${C_GREEN}Username:${C_RESET}  $USERNAME"
echo
echo -e "${C_YELLOW}XFCE + LightDM + NetworkManager + GRUB installed.${C_RESET}"
echo
echo -e "${C_GREEN}Remove the USB drive and reboot.${C_RESET}"
echo
echo -e "${C_CYAN}======================================================${C_RESET}"
echo
