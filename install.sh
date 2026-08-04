#!/usr/bin/env bash
set -e

echo "=== 1. Cleaning Server Packages & Setting Desktop Identity ==="
# Remove server-specific management tools and set Fedora Workstation branding
sudo dnf remove -y cockpit* fedora-release-server || true
sudo dnf install -y fedora-release-workstation fedora-repos
sudo systemctl set-default graphical.target

echo "=== 2. Updating System & Enabling Repositories (RPM Fusion, Flathub, COPRs) ==="
sudo dnf update -y

# Enable RPM Fusion (Free & Non-Free)
sudo dnf install -y \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# Enable Flathub
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# Enable COPR Repositories for Caelestia Shell dependencies
sudo dnf copr enable -y errornointernet/quickshell
sudo dnf copr enable -y celestelove/libcava
sudo dnf copr enable -y celestelove/app2unit
sudo dnf copr enable -y brycensranch/gpu-screen-recorder-git
sudo dnf copr enable -y celestelove/caelestia

sudo dnf check-update || true

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

echo "=== 4. Installing Native Fedora (RPM) Packages ==="
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

echo "=== 5. Installing Flatpak Applications ==="
flatpak install -y flathub com.visualstudio.code
flatpak install -y flathub com.usebottles.bottles
flatpak install -y flathub net.lutris.Lutris
flatpak install -y flathub org.prismlauncher.PrismLauncher
flatpak install -y flathub com.discordapp.Discord
flatpak install -y flathub com.pokemmo.PokeMMO

echo "=== 6. Setting up Native Discord ==="
TMP_DISCORD=$(mktemp -d)
curl -L "https://discord.com/api/download?platform=linux&format=tar.gz" -o "$TMP_DISCORD/discord.tar.gz"
sudo tar -xzf "$TMP_DISCORD/discord.tar.gz" -C /opt/
sudo ln -sf /opt/Discord/Discord /usr/local/bin/discord-native
rm -rf "$TMP_DISCORD"

echo "=== 7. Setting up Windows Compatibility Helpers (Affinity) ==="
git clone https://github.com/ryzendew/Linux-Affinity-Installer.git ~/.local/share/affinity-installer || true

echo "=== 8. Configuring Hyprland Autostart for Caelestia ==="
mkdir -p ~/.config/hypr
HYPR_CONF=~/.config/hypr/hyprland.conf

if [ ! -f "$HYPR_CONF" ]; then
  touch "$HYPR_CONF"
fi

if ! grep -q "caelestia shell -d" "$HYPR_CONF"; then
  echo "" >> "$HYPR_CONF"
  echo "# Autostart Caelestia Shell" >> "$HYPR_CONF"
  echo "exec-once = caelestia shell -d" >> "$HYPR_CONF"
fi

echo "====================================================================="
echo "INSTALLATION COMPLETE!"
echo "Server packages removed, desktop setup ready."
echo "====================================================================="
