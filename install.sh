#!/bin/bash
set -eo pipefail

# ANSI Colors
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_RED="\033[1;31m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_CYAN="\033[1;36m"
C_MAGENTA="\033[1;35m"

# Safe unmount helper
safe_umount() {
    swapoff -a 2>/dev/null || true
    umount -l /mnt/dev 2>/dev/null || true
    umount -l /mnt/proc 2>/dev/null || true
    umount -l /mnt/sys 2>/dev/null || true
    umount -l /mnt/run 2>/dev/null || true
    umount -R /mnt 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# MODULE 1: DISK FORMATTING & PARTITIONING
# ------------------------------------------------------------------------------
format_disk() {
    clear
    echo -e "${C_CYAN}======================================================${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}             MODULE 1: DISK FORMATTER                 ${C_RESET}"
    echo -e "${C_CYAN}======================================================${C_RESET}\n"

    lsblk -o NAME,SIZE,TYPE,MODEL,MOUNTPOINTS | grep -E "disk|part"
    echo -e "\n${C_YELLOW}------------------------------------------------------${C_RESET}"

    read -p "$(echo -e ${C_BOLD}"Enter target disk name (e.g., sda, nvme0n1): "${C_RESET})" DISK_NAME
    DISK="/dev/${DISK_NAME}"

    if [ ! -b "$DISK" ]; then
        echo -e "${C_RED}Error: Device $DISK does not exist!${C_RESET}"
        return 1
    fi

    read -p "$(echo -e ${C_BOLD}"Enter Swap size in GB (e.g., 2, 4, 8): "${C_RESET})" SWAP_SIZE

    if [[ "$DISK" == *"nvme"* ]] || [[ "$DISK" == *"mmcblk"* ]]; then
        PART_EFI="${DISK}p1"
        PART_SWAP="${DISK}p2"
        PART_ROOT="${DISK}p3"
    else
        PART_EFI="${DISK}1"
        PART_SWAP="${DISK}2"
        PART_ROOT="${DISK}3"
    fi

    echo -e "\n${C_RED}${C_BOLD}WARNING: ALL DATA ON $DISK WILL BE PERMANENTLY ERASED!${C_RESET}"
    read -p "$(echo -e ${C_RED}"Type 'YES' to format $DISK: "${C_RESET})" CONFIRM

    if [ "$CONFIRM" != "YES" ]; then
        echo -e "${C_YELLOW}Disk formatting canceled.${C_RESET}"
        return 0
    fi

    safe_umount

    echo -e "\n${C_MAGENTA}==> Wiping disk metadata...${C_RESET}"
    wipefs -af "$DISK" 2>/dev/null || true

    echo -e "${C_MAGENTA}==> Writing GPT partition table...${C_RESET}"
    sfdisk "$DISK" <<EOF
label: gpt
size=512M, type=U, name="EFI"
size=${SWAP_SIZE}G, type=S, name="SWAP"
size=+, type=L, name="ROOT"
EOF

    # Force Kernel Partition Table Sync
    blockdev --rereadpt "$DISK" 2>/dev/null || true
    udevadm trigger --subsystem-match=block 2>/dev/null || true
    udevadm settle 2>/dev/null || true

    # Wait for block nodes
    for part in "$PART_EFI" "$PART_SWAP" "$PART_ROOT"; do
        count=0
        while [ ! -b "$part" ]; do
            sleep 0.5
            count=$((count+1))
            if [ $count -gt 10 ]; then
                echo -e "${C_RED}Error: Partition $part not found.${C_RESET}"
                return 1
            fi
        done
    done

    echo -e "${C_MAGENTA}==> Formatting Filesystems...${C_RESET}"
    mkfs.vfat -F32 "$PART_EFI"
    mkswap -f "$PART_SWAP"
    mkfs.ext4 -F "$PART_ROOT"

    echo -e "${C_GREEN}\nDisk formatting completed successfully!${C_RESET}"
    read -p "Press [ENTER] to return to menu..."
}

# ------------------------------------------------------------------------------
# MODULE 2: XFCE RICING & DOTFILES DEPLOYMENT
# ------------------------------------------------------------------------------
rice_xfce() {
    clear
    echo -e "${C_CYAN}======================================================${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}             MODULE 2: XFCE RICER                     ${C_RESET}"
    echo -e "${C_CYAN}======================================================${C_RESET}\n"

    # Identify user context
    TARGET_USER="${SUDO_USER:-$USER}"
    if [ "$TARGET_USER" = "root" ]; then
        read -p "Enter username to apply rice to: " TARGET_USER
    fi

    USER_HOME=$(eval echo "~$TARGET_USER")

    if [ ! -d "$USER_HOME" ]; then
        echo -e "${C_RED}Error: Home directory for $TARGET_USER does not exist!${C_RESET}"
        return 1
    fi

    echo -e "${C_MAGENTA}==> Target User: $TARGET_USER ($USER_HOME)${C_RESET}"
    read -p "Apply dotfiles rice now? (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        return 0
    fi

    # Create config structure
    mkdir -p "$USER_HOME/.config" "$USER_HOME/.themes" "$USER_HOME/.icons" "$USER_HOME/.local/share/fonts"

    # Fetch dotfiles
    TEMP_DIR=$(mktemp -d)
    echo -e "${C_MAGENTA}==> Downloading custom dotfiles repository...${C_RESET}"
    git clone --depth 1 https://github.com/mehedirm6244/My_XFCE_dotties.git "$TEMP_DIR"

    SRC_DIR="$TEMP_DIR"
    if [ -d "$TEMP_DIR/Dotfiles" ]; then
        SRC_DIR="$TEMP_DIR/Dotfiles"
    fi

    echo -e "${C_MAGENTA}==> Applying configurations, themes, and icons...${C_RESET}"
    shopt -s dotglob
    [ -d "$SRC_DIR/.config" ] && cp -r "$SRC_DIR/.config/"* "$USER_HOME/.config/" 2>/dev/null || true
    [ -d "$SRC_DIR/.themes" ] && cp -r "$SRC_DIR/.themes/"* "$USER_HOME/.themes/" 2>/dev/null || true
    [ -d "$SRC_DIR/.icons" ] && cp -r "$SRC_DIR/.icons/"* "$USER_HOME/.icons/" 2>/dev/null || true
    shopt -u dotglob

    # Cleanup temp directory
    rm -rf "$TEMP_DIR"

    # Fix file permissions for non-root target user
    chown -R "$TARGET_USER:$(id -gn $TARGET_USER)" "$USER_HOME/.config" "$USER_HOME/.themes" "$USER_HOME/.icons" 2>/dev/null || true

    echo -e "${C_GREEN}\nXFCE Rice applied successfully for $TARGET_USER!${C_RESET}"
    echo -e "${C_YELLOW}Note: Log out and log back in for Xfconf settings to reload completely.${C_RESET}"
    read -p "Press [ENTER] to return to menu..."
}

# ------------------------------------------------------------------------------
# MAIN INTERACTIVE MENU
# ------------------------------------------------------------------------------
while true; do
    clear
    echo -e "${C_CYAN}======================================================${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}          SYSTEM MANAGEMENT & RICE MENU              ${C_RESET}"
    echo -e "${C_CYAN}======================================================${C_RESET}\n"
    echo "1) Format Disk (Partition GPT, Create Swap/EFI/Root, Format)"
    echo "2) Rice XFCE (Deploy Custom Dotfiles, Themes & Icons)"
    echo "3) Run Full Sequence (Format Disk -> Rice XFCE)"
    echo "4) Exit"
    echo ""
    read -p "Select an option [1-4]: " MENU_CHOICE

    case "$MENU_CHOICE" in
        1)
            format_disk
            ;;
        2)
            rice_xfce
            ;;
        3)
            format_disk && rice_xfce
            ;;
        4)
            echo -e "${C_GREEN}Exiting.${C_RESET}"
            exit 0
            ;;
        *)
            echo -e "${C_RED}Invalid option selected.${C_RESET}"
            sleep 1
            ;;
    esac
done
