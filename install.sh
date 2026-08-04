#!/usr/bin/env bash

echo "=== 1. Setting Sudo Password Cache ==="
echo "Defaults timestamp_timeout=-1" | sudo tee /etc/sudoers.d/99-no-password-timeout
sudo chmod 0440 /etc/sudoers.d/99-no-password-timeout

echo "=== 2. Updating System & Repositories ==="
sudo dnf update -y

# Enable RPM Fusion
sudo dnf install -y \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# Enable Flathub
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# Enable COPR Repositories
sudo dnf copr enable -y errornointernet/quickshell
sudo dnf copr enable -y celestelove/libcava
sudo dnf copr enable -y celestelove/app2unit
sudo dnf copr enable -y brycensranch/gpu-screen-recorder-git
sudo dnf copr enable -y celestelove/caelestia

echo "=== 3. Installing Hyprland & Caelestia Shell ==="
sudo dnf install -y \
  hyprland \
  xdg-desktop-portal-hyprland \
  fish \
  git \
  quickshell-git \
  libcava-devel \
  app2unit \
  gpu-screen-recorder-ui \
  caelestia-shell \
  caelestia-cli

echo "=== 4. Installing RPM Applications ==="
sudo dnf install -y \
  godot \
  mgba \
  libreoffice \
  firefox \
  transmission \
  vlc \
  baobab \
  gparted \
  steam \
  wine \
  winetricks \
  python3-pyqt6 \
  python3-pyqt6-svg

echo "=== 5. Installing Flatpaks ==="
flatpak install -y flathub com.visualstudio.code
flatpak install -y flathub com.usebottles.bottles
flatpak install -y flathub net.lutris.Lutris
flatpak install -y flathub org.prismlauncher.PrismLauncher
flatpak install -y flathub com.discordapp.Discord
flatpak install -y flathub com.pokemmo.PokeMMO

echo "=== 6. Configuring Hyprland ==="
mkdir -p ~/.config/hypr
HYPR_CONF=~/.config/hypr/hyprland.conf
touch "$HYPR_CONF"

if ! grep -q "caelestia shell -d" "$HYPR_CONF"; then
  echo "exec-once = caelestia shell -d" >> "$HYPR_CONF"
fi

echo "Done!"
