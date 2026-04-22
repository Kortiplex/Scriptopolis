#!/usr/bin/env bash
set -euo pipefail

ROOT_PASSWORD="pw"
DEV_USER="kortiplex"
DEV_PASSWORD="pw"

PACMAN_PACKAGES=(
	openssh github-cli pv fzf clang llvm rust python-pip lm_sensors psutils
	python-psutil neofetch htop bashtop imagemagick jq zsh lolcat ripgrep bat
	bat-extras lsd cowsay ponysay cmatrix nyancat doge fortune-mod figlet
)

YAY_PACKAGES=(
	figlet-fonts figlet-fonts-extra pipes.sh boxes asciiquarium-transparent-git
)

log() {
	printf '\n[%s] %s\n' "setup" "$*"
}

as_user() {
	local user="$1"
	shift
	su - "$user" -c "$*"
}

ensure_root() {
	if [[ "$(id -u)" -ne 0 ]]; then
		echo "This script must run as root." >&2
		exit 1
	fi
}

ensure_sudoers_for_wheel() {
	local sudoers_d_file="/etc/sudoers.d/00-wheel"
	if [[ ! -f "$sudoers_d_file" ]]; then
		log "Enabling sudo for wheel group"
		printf '%%wheel ALL=(ALL:ALL) ALL\n' > "$sudoers_d_file"
		chmod 0440 "$sudoers_d_file"
	fi
}

set_passwords() {
	log "Setting root password"
	echo "root:${ROOT_PASSWORD}" | chpasswd

	if id -u "$DEV_USER" >/dev/null 2>&1; then
		log "User $DEV_USER already exists"
	else
		log "Creating user $DEV_USER"
		useradd -m -G wheel -s /usr/bin/zsh "$DEV_USER"
	fi

	log "Setting password for $DEV_USER"
	echo "${DEV_USER}:${DEV_PASSWORD}" | chpasswd
}

init_pacman() {
	log "Initializing pacman keyring"
	pacman-key --init || true
	pacman-key --populate archlinux || true

	log "Updating package databases"
	pacman -Syy --noconfirm

	log "Upgrading system and keyring"
	pacman -Syu --noconfirm
	pacman -S --needed --noconfirm archlinux-keyring

	log "Installing bootstrap tools"
	pacman -S --needed --noconfirm base-devel git sudo curl
}

install_pacman_packages() {
	local installable=()
	local missing=()
	local pkg

	for pkg in "${PACMAN_PACKAGES[@]}"; do
		if pacman -Qi "$pkg" >/dev/null 2>&1; then
			continue
		fi

		if pacman -Si "$pkg" >/dev/null 2>&1; then
			installable+=("$pkg")
		else
			missing+=("$pkg")
		fi
	done

	if ((${#installable[@]} > 0)); then
		log "Installing pacman packages"
		pacman -S --needed --noconfirm "${installable[@]}"
	else
		log "Requested pacman packages are already installed"
	fi

	if ((${#missing[@]} > 0)); then
		log "Not in official repos, will try with yay: ${missing[*]}"
		YAY_PACKAGES+=("${missing[@]}")
	fi
}

install_yay() {
	if command -v yay >/dev/null 2>&1; then
		log "yay is already installed"
		return
	fi

	log "Installing yay as $DEV_USER"
	as_user "$DEV_USER" "rm -rf ~/yay && git clone https://aur.archlinux.org/yay.git ~/yay"
	as_user "$DEV_USER" "cd ~/yay && makepkg -si --noconfirm"
	as_user "$DEV_USER" "rm -rf ~/yay"
}

install_yay_packages() {
	if ((${#YAY_PACKAGES[@]} == 0)); then
		return
	fi

	log "Installing yay packages as $DEV_USER"
	as_user "$DEV_USER" "yay -S --needed --noconfirm ${YAY_PACKAGES[*]}"
}

install_homebrew() {
	if as_user "$DEV_USER" "command -v brew >/dev/null 2>&1"; then
		log "Homebrew is already installed for $DEV_USER"
		return
	fi

	log "Installing Homebrew as $DEV_USER"
	as_user "$DEV_USER" "NONINTERACTIVE=1 /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""

	local zprofile="/home/${DEV_USER}/.zprofile"
	local bashrc="/home/${DEV_USER}/.bashrc"
	local shellenv='eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"'

	if ! grep -Fq "$shellenv" "$zprofile" 2>/dev/null; then
		echo "$shellenv" >> "$zprofile"
	fi
	if ! grep -Fq "$shellenv" "$bashrc" 2>/dev/null; then
		echo "$shellenv" >> "$bashrc"
	fi

	chown "$DEV_USER:$DEV_USER" "$zprofile" "$bashrc"
}

install_opencode() {
	log "Installing opencode via Homebrew as $DEV_USER"
	as_user "$DEV_USER" 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"; if brew list --formula opencode >/dev/null 2>&1; then echo "opencode already installed"; else brew install anomalyco/tap/opencode; fi'
}

set_default_wsl_user() {
	log "Setting default WSL user to $DEV_USER"
	cat > /etc/wsl.conf <<EOF
[user]
default=$DEV_USER
EOF
}

main() {
	ensure_root
	init_pacman
	set_passwords
	ensure_sudoers_for_wheel
	install_pacman_packages
	install_yay
	install_yay_packages
	install_homebrew
	install_opencode
	set_default_wsl_user

	log "Setup complete. Restart WSL to apply default user change."
}

main "$@"