#!/bin/bash
set -e

# Clear screen and ensure root execution
clear
if [ "$(id -u)" -ne 0 ]; then
  echo "Error: Please run this script with sudo or as root!"
  exit 1
fi

echo "======================================================"
echo "   AUTOMATED VOID LINUX + CUSTOM XFCE RICE INSTALLER  "
echo "======================================================"
echo ""

# 1. Select Target Drive
echo "Available Storage Drives:"
lsblk -d -n -o NAME,SIZE,TYPE,MODEL | grep -E "disk"
echo ""
read -p "Enter target disk name (e.g., sda, nvme0n1): " DISK_NAME
DISK="/dev/${DISK_NAME}"

if [ ! -b "$DISK" ]; then
    echo "Error: Device $DISK does not exist!"
    exit 1
fi

# Determine partition naming scheme (e.g., /dev/sda1 vs /dev/nvme0n1p1)
if [[ "$DISK" == *"nvme"* ]] || [[ "$DISK" == *"mmcblk"* ]]; then
    PART_EFI="${DISK}p1"
    PART_SWAP="${DISK}p2"
    PART_ROOT="${DISK}p3"
else
    PART_EFI="${DISK}1"
    PART_SWAP="${DISK}2"
    PART_ROOT="${DISK}3"
fi

# 2. Gather User Inputs & Swap Choice
echo ""
read -p "Enter Swap size in GB (e.g., 2, 4, 8): " SWAP_SIZE
read -p "Enter your desired Username: " USERNAME
read -sp "Enter Password for $USERNAME: " USER_PASS
echo ""
read -sp "Enter Root Password: " ROOT_PASS
echo ""
echo ""

# 3. Confirmation Warning
echo "------------------------------------------------------"
echo " WARNING: ALL DATA ON $DISK WILL BE DELETED!"
echo " Target Disk:     $DISK"
echo " EFI Partition:   $PART_EFI (512MB)"
echo " Swap Partition:  $PART_SWAP (${SWAP_SIZE}GB)"
echo " Root Partition:  $PART_ROOT (Remaining Space)"
echo " Username:        $USERNAME"
echo " Custom Dotfiles: https://github.com/mehedirm6244/My_XFCE_dotties"
echo "------------------------------------------------------"
read -p "Type 'YES' to start installation: " CONFIRM

if [ "$CONFIRM" != "YES" ]; then
    echo "Installation canceled."
    exit 1
fi

echo ""
echo "==> [1/7] Wiping and Partitioning $DISK (GPT)..."
sfdisk "$DISK" <<EOF
label: gpt
size=512M, type=U, name="EFI"
size=${SWAP_SIZE}G, type=S, name="SWAP"
size=+, type=L, name="ROOT"
EOF

echo "==> [2/7] Formatting partitions..."
mkfs.vfat -F32 "$PART_EFI"
mkswap "$PART_SWAP"
mkfs.ext4 -F "$PART_ROOT"

echo "==> [3/7] Mounting filesystems..."
mount "$PART_ROOT" /mnt
mkdir -p /mnt/boot/efi
mount "$PART_EFI" /mnt/boot/efi
swapon "$PART_SWAP"

echo "==> [4/7] Installing Base System, Desktop, Fonts, and Apps..."
XBPS_ARCH=x86_64 xbps-install -Sy -R https://repo-default.voidlinux.org/current -r /mnt \
  base-system xfce4 Thunar lightdm lightdm-gtk-greeter grub-x86_64-efi NetworkManager \
  git curl wget picom plank cava jq htop unzip ca-certificates sudo \
  elogind polkitd Roboto-fonts jetbrains-mono

echo "==> [5/7] Generating /etc/fstab and DNS settings..."
mkdir -p /mnt/etc
UUID_ROOT=$(blkid -s UUID -o value "$PART_ROOT")
UUID_EFI=$(blkid -s UUID -o value "$PART_EFI")
UUID_SWAP=$(blkid -s UUID -o value "$PART_SWAP")

cat <<EOF > /mnt/etc/fstab
UUID=$UUID_ROOT / ext4 defaults 0 1
UUID=$UUID_EFI /boot/efi vfat defaults 0 2
UUID=$UUID_SWAP swap swap defaults 0 0
EOF

# Copy DNS config so network works inside chroot
cp /etc/resolv.conf /mnt/etc/resolv.conf

echo "==> [6/7] Configuring System, User, Services, and Dotfiles..."

# Bind essential API filesystems for GRUB EFI access
for sysfs in /dev /proc /sys /run; do
    mount --bind "$sysfs" "/mnt$sysfs"
done

chroot /mnt /bin/bash <<EOF
# Set Passwords
echo "root:$ROOT_PASS" | chpasswd
useradd -m -G wheel,audio,video,input,storage -s /bin/bash "$USERNAME"
echo "$USERNAME:$USER_PASS" | chpasswd

# Grant Sudo rights to wheel group with strict secure permissions
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel

# Enable necessary runit services
ln -s /etc/sv/dbus /etc/runit/runsvdir/default/
ln -s /etc/sv/elogind /etc/runit/runsvdir/default/
ln -s /etc/sv/polkitd /etc/runit/runsvdir/default/
ln -s /etc/sv/lightdm /etc/runit/runsvdir/default/
ln -s /etc/sv/NetworkManager /etc/runit/runsvdir/default/

# Target home directory
USER_HOME="/home/$USERNAME"
mkdir -p "\$USER_HOME/.config" "\$USER_HOME/.themes" "\$USER_HOME/.icons"

# Enable dotglob so hidden files are included in wildcards
shopt -s dotglob

# Clone dotfiles
rm -rf "\$USER_HOME/dotties_temp"
git clone --depth 1 https://github.com/mehedirm6244/My_XFCE_dotties.git "\$USER_HOME/dotties_temp"

# Auto-detect dotfile tree structure (handles direct or nested /Dotfiles layout)
SRC_DIR="\$USER_HOME/dotties_temp"
if [ -d "\$USER_HOME/dotties_temp/Dotfiles" ]; then
    SRC_DIR="\$USER_HOME/dotties_temp/Dotfiles"
fi

if [ -d "\$SRC_DIR" ]; then
    [ -d "\$SRC_DIR/.config" ] && cp -r "\$SRC_DIR/.config/"* "\$USER_HOME/.config/" 2>/dev/null || true
    [ -d "\$SRC_DIR/.themes" ] && cp -r "\$SRC_DIR/.themes/"* "\$USER_HOME/.themes/" 2>/dev/null || true
    [ -d "\$SRC_DIR/.icons" ] && cp -r "\$SRC_DIR/.icons/"* "\$USER_HOME/.icons/" 2>/dev/null || true
    rm -rf "\$USER_HOME/dotties_temp"
fi

# Disable dotglob back to default
shopt -u dotglob

# Fix ownership permissions for the user
chown -R "$USERNAME:$USERNAME" "\$USER_HOME"

# Re-generate initramfs images explicitly before GRUB installation
dracut --regenerate-all --force

# Install GRUB bootloader
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="Void"
update-grub
EOF

echo "==> [7/7] Unmounting partitions..."
# Safely unmount bound virtual filesystems
umount -l /mnt/dev || true
umount -l /mnt/proc || true
umount -l /mnt/sys || true
umount -l /mnt/run || true

swapoff "$PART_SWAP"
umount -R /mnt

echo ""
echo "======================================================"
echo "    INSTALLATION COMPLETE! YOU CAN REBOOT NOW         "
echo "======================================================"
