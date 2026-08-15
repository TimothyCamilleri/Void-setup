#!/bin/bash
set -e

# Clear screen and ensure root execution
clear
if [ "$(id -u)" -ne 0 ]; then
  echo "Error: Please run this script with sudo or as root!"
  exit 1
fi

echo "======================================================"
echo "    AUTOMATED VOID LINUX + XFCE INSTALLER (W/ SWAP)   "
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

echo "==> [4/7] Installing Void Linux Base System & XFCE..."
# Installs packages locally from Live ISO cache for maximum speed
XBPS_ARCH=$(uname -m) xbps-install -Sy -R /hostbuf/binpkgs -r /mnt \
  base-system xfce4 lightdm lightdm-gtk-greeter grub-x86_64-efi NetworkManager

echo "==> [5/7] Generating /etc/fstab..."
mkdir -p /mnt/etc
UUID_ROOT=$(blkid -s UUID -o value "$PART_ROOT")
UUID_EFI=$(blkid -s UUID -o value "$PART_EFI")
UUID_SWAP=$(blkid -s UUID -o value "$PART_SWAP")

cat <<EOF > /mnt/etc/fstab
UUID=$UUID_ROOT / ext4 defaults 0 1
UUID=$UUID_EFI /boot/efi vfat defaults 0 2
UUID=$UUID_SWAP swap swap defaults 0 0
EOF

echo "==> [6/7] Configuring Users, Sudo, Services, and Bootloader..."
xchroot /mnt /bin/bash <<EOF
# Set Passwords
echo "root:$ROOT_PASS" | chpasswd
useradd -m -G wheel,audio,video,input,storage -s /bin/bash "$USERNAME"
echo "$USERNAME:$USER_PASS" | chpasswd

# Grant Sudo rights to wheel group
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

# Enable necessary runit services
ln -s /etc/sv/dbus /etc/runit/runsvdir/default/
ln -s /etc/sv/lightdm /etc/runit/runsvdir/default/
ln -s /etc/sv/NetworkManager /etc/runit/runsvdir/default/

# Install GRUB bootloader
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="Void"
update-grub
EOF

echo "==> [7/7] Unmounting partitions..."
swapoff "$PART_SWAP"
umount -R /mnt

echo ""
echo "======================================================"
echo "    INSTALLATION COMPLETE! YOU CAN REBOOT NOW         "
echo "======================================================"
