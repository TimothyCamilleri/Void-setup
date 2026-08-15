#!/bin/bash
set -eo pipefail

# Define ANSI Color Codes
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_RED="\033[1;31m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_CYAN="\033[1;36m"
C_MAGENTA="\033[1;35m"

# Cleanup trap to unmount everything safely on unexpected failure
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo -e "\n${C_RED}======================================================${C_RESET}"
        echo -e "${C_RED} ERROR OCCURRED! Cleaning up mounted filesystems...  ${C_RESET}"
        echo -e "${C_RED}======================================================${C_RESET}"
        umount -l /mnt/dev 2>/dev/null || true
        umount -l /mnt/proc 2>/dev/null || true
        umount -l /mnt/sys 2>/dev/null || true
        umount -l /mnt/run 2>/dev/null || true
        swapoff -a 2>/dev/null || true
        umount -R /mnt 2>/dev/null || true
    fi
}
trap cleanup EXIT

clear
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${C_RED}Error: Please run this script with sudo or as root!${C_RESET}"
  exit 1
fi

echo -e "${C_CYAN}======================================================${C_RESET}"
echo -e "${C_CYAN}${C_BOLD}   AUTOMATED VOID LINUX + CUSTOM XFCE RICE INSTALLER  ${C_RESET}"
echo -e "${C_CYAN}======================================================${C_RESET}\n"

# Pre-flight Check: Internet Connection
echo -e "${C_MAGENTA}==> Verifying network connectivity...${C_RESET}"
if ! ping -c 1 -W 3 repo-default.voidlinux.org >/dev/null 2>&1; then
    echo -e "${C_RED}Error: No internet connection detected or mirror is unreachable.${C_RESET}"
    echo -e "${C_RED}Please configure your network before running this script.${C_RESET}"
    exit 1
fi
echo -e "${C_GREEN}Network OK.${C_RESET}\n"

# 1. Select Target Drive
echo -e "${C_YELLOW}Available Storage Drives:${C_RESET}"
lsblk -d -n -o NAME,SIZE,TYPE,MODEL | grep -E "disk"
echo ""
read -p "$(echo -e ${C_BOLD}"Enter target disk name (e.g., sda, nvme0n1): "${C_RESET})" DISK_NAME
DISK="/dev/${DISK_NAME}"

if [ ! -b "$DISK" ]; then
    echo -e "${C_RED}Error: Device $DISK does not exist!${C_RESET}"
    exit 1
fi

# Ensure drive isn't actively mounted
if grep -qs "$DISK" /proc/mounts; then
    echo -e "${C_RED}Error: Disk $DISK or one of its partitions is currently mounted!${C_RESET}"
    echo -e "${C_RED}Unmount the drive and run the script again.${C_RESET}"
    exit 1
fi

# Determine partition naming scheme
if [[ "$DISK" == *"nvme"* ]] || [[ "$DISK" == *"mmcblk"* ]]; then
    PART_EFI="${DISK}p1"
    PART_SWAP="${DISK}p2"
    PART_ROOT="${DISK}p3"
else
    PART_EFI="${DISK}1"
    PART_SWAP="${DISK}2"
    PART_ROOT="${DISK}3"
fi

# 2. Gather User Inputs
echo ""
read -p "$(echo -e ${C_BOLD}"Enter Swap size in GB (e.g., 2, 4, 8): "${C_RESET})" SWAP_SIZE
read -p "$(echo -e ${C_BOLD}"Enter your desired Username: "${C_RESET})" USERNAME
read -sp "$(echo -e ${C_BOLD}"Enter Password for $USERNAME: "${C_RESET})" USER_PASS
echo ""
read -sp "$(echo -e ${C_BOLD}"Enter Root Password: "${C_RESET})" ROOT_PASS
echo -e "\n"

# Verify inputs aren't empty
if [ -z "$USERNAME" ] || [ -z "$USER_PASS" ] || [ -z "$ROOT_PASS" ] || [ -z "$SWAP_SIZE" ]; then
    echo -e "${C_RED}Error: All input fields are required.${C_RESET}"
    exit 1
fi

# 3. Confirmation Warning
echo -e "${C_RED}------------------------------------------------------${C_RESET}"
echo -e "${C_RED}${C_BOLD} WARNING: ALL DATA ON $DISK WILL BE DELETED!${C_RESET}"
echo -e "${C_YELLOW} Target Disk:     ${C_RESET}${C_BOLD}$DISK${C_RESET}"
echo -e "${C_YELLOW} EFI Partition:   ${C_RESET}$PART_EFI (512MB)"
echo -e "${C_YELLOW} Swap Partition:  ${C_RESET}$PART_SWAP (${SWAP_SIZE}GB)"
echo -e "${C_YELLOW} Root Partition:  ${C_RESET}$PART_ROOT (Remaining Space)"
echo -e "${C_YELLOW} Username:        ${C_RESET}$USERNAME"
echo -e "${C_YELLOW} Custom Dotfiles: ${C_RESET}https://github.com/mehedirm6244/My_XFCE_dotties"
echo -e "${C_RED}------------------------------------------------------${C_RESET}"
read -p "$(echo -e ${C_RED}${C_BOLD}"Type 'YES' to start installation: "${C_RESET})" CONFIRM

if [ "$CONFIRM" != "YES" ]; then
    echo -e "${C_YELLOW}Installation canceled.${C_RESET}"
    exit 1
fi

echo -e "\n${C_MAGENTA}==> [1/7] Wiping and Partitioning $DISK (GPT)...${C_RESET}"
sfdisk "$DISK" <<EOF
label: gpt
size=512M, type=U, name="EFI"
size=${SWAP_SIZE}G, type=S, name="SWAP"
size=+, type=L, name="ROOT"
EOF

echo -e "${C_MAGENTA}==> [2/7] Formatting partitions...${C_RESET}"
mkfs.vfat -F32 "$PART_EFI"
mkswap "$PART_SWAP"
mkfs.ext4 -F "$PART_ROOT"

echo -e "${C_MAGENTA}==> [3/7] Mounting filesystems...${C_RESET}"
mount "$PART_ROOT" /mnt
mkdir -p /mnt/boot/efi
mount "$PART_EFI" /mnt/boot/efi
swapon "$PART_SWAP"

echo -e "${C_MAGENTA}==> [4/7] Installing Base System, Desktop, Fonts, and Apps...${C_RESET}"
XBPS_ARCH=x86_64 xbps-install -Sy -R https://repo-default.voidlinux.org/current -r /mnt \
  base-system xfce4 Thunar lightdm lightdm-gtk-greeter grub-x86_64-efi NetworkManager \
  git curl wget picom plank cava jq htop unzip ca-certificates sudo \
  elogind polkitd Roboto-fonts jetbrains-mono

echo -e "${C_MAGENTA}==> [5/7] Generating /etc/fstab and DNS settings...${C_RESET}"
mkdir -p /mnt/etc
UUID_ROOT=$(blkid -s UUID -o value "$PART_ROOT")
UUID_EFI=$(blkid -s UUID -o value "$PART_EFI")
UUID_SWAP=$(blkid -s UUID -o value "$PART_SWAP")

cat <<EOF > /mnt/etc/fstab
UUID=$UUID_ROOT / ext4 defaults 0 1
UUID=$UUID_EFI /boot/efi vfat defaults 0 2
UUID=$UUID_SWAP swap swap defaults 0 0
EOF

cp /etc/resolv.conf /mnt/etc/resolv.conf

echo -e "${C_MAGENTA}==> [6/7] Configuring System, User, Services, and Dotfiles...${C_RESET}"

# Bind API filesystems for chroot EFI & device access
for sysfs in /dev /proc /sys /run; do
    mount --bind "$sysfs" "/mnt$sysfs"
done

# Pass host variables explicitly to chroot environment
export ROOT_PASS USERNAME USER_PASS

chroot /mnt /bin/bash <<'EOF'
set -e

# Set Passwords
echo "root:$ROOT_PASS" | chpasswd
useradd -m -G wheel,audio,video,input,storage -s /bin/bash "$USERNAME"
echo "$USERNAME:$USER_PASS" | chpasswd

# Sudo setup for wheel group
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel

# Enable runit services
ln -s /etc/sv/dbus /etc/runit/runsvdir/default/
ln -s /etc/sv/elogind /etc/runit/runsvdir/default/
ln -s /etc/sv/polkitd /etc/runit/runsvdir/default/
ln -s /etc/sv/lightdm /etc/runit/runsvdir/default/
ln -s /etc/sv/NetworkManager /etc/runit/runsvdir/default/

# Dotfiles deployment
USER_HOME="/home/$USERNAME"
mkdir -p "$USER_HOME/.config" "$USER_HOME/.themes" "$USER_HOME/.icons"

shopt -s dotglob
rm -rf "$USER_HOME/dotties_temp"
git clone --depth 1 https://github.com/mehedirm6244/My_XFCE_dotties.git "$USER_HOME/dotties_temp"

SRC_DIR="$USER_HOME/dotties_temp"
if [ -d "$USER_HOME/dotties_temp/Dotfiles" ]; then
    SRC_DIR="$USER_HOME/dotties_temp/Dotfiles"
fi

if [ -d "$SRC_DIR" ]; then
    [ -d "$SRC_DIR/.config" ] && cp -r "$SRC_DIR/.config/"* "$USER_HOME/.config/" 2>/dev/null || true
    [ -d "$SRC_DIR/.themes" ] && cp -r "$SRC_DIR/.themes/"* "$USER_HOME/.themes/" 2>/dev/null || true
    [ -d "$SRC_DIR/.icons" ] && cp -r "$SRC_DIR/.icons/"* "$USER_HOME/.icons/" 2>/dev/null || true
    rm -rf "$USER_HOME/dotties_temp"
fi
shopt -u dotglob

chown -R "$USERNAME:$USERNAME" "$USER_HOME"

# Re-generate initramfs images explicitly before GRUB installation
dracut --regenerate-all --force

# Install GRUB bootloader
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="Void"
update-grub
EOF

echo -e "${C_MAGENTA}==> [7/7] Unmounting partitions cleanly...${C_RESET}"
umount -l /mnt/dev || true
umount -l /mnt/proc || true
umount -l /mnt/sys || true
umount -l /mnt/run || true

swapoff "$PART_SWAP"
umount -R /mnt

# Disable trap after successful completion
trap - EXIT

echo -e "\n${C_GREEN}======================================================${C_RESET}"
echo -e "${C_GREEN}${C_BOLD}    INSTALLATION COMPLETE! YOU CAN REBOOT NOW         ${C_RESET}"
echo -e "${C_GREEN}======================================================${C_RESET}"
