#!/bin/bash
set -e

if [[ "$EUID" -ne 0 ]]; then
	echo 'script must be run as root' >&2
	exit 1
fi

# FROM ENVIRONMENT
# - ADMIN_USER
# - NO_DOCKER_GROUP
# - WSL_HOSTNAME
# - ESSENTIAL_TOOLS
# - DEV_TOOLS
# - CROSS_DEV_TOOLS

DEFAULT_PASSWORD="archlinux"

# update package db (y) and pacman
pacman -Sy --noconfirm --needed pacman
# update the entire system
pacman -Su --noconfirm

# fixes errors like: D8AFDDA07A5B6EDFA7D8CCDAD6D055F927843F1C could not be locally signed.
# https://www.archlinux.org/news/gnupg-21-and-the-pacman-keyring/
rm -rf /etc/pacman.d/gnupg &>/dev/null
pacman-key --init
pacman-key --populate archlinux

echo 'LANG=en_US.UTF-8' > /etc/locale.conf
locale-gen

if [[ -n "$ADMIN_USER" ]]; then
	useradd -m "$ADMIN_USER"
	usermod -aG wheel "$ADMIN_USER"
	echo "$ADMIN_USER:$DEFAULT_PASSWORD" | chpasswd
	pacman -S --noconfirm --needed sudo shadow sed # shadow is for chpasswd

	if grep "# %wheel ALL=(ALL) ALL" /etc/sudoers &>/dev/null; then
		# uncomment it if in the expected form
		sed '/^# %wheel ALL=(ALL) ALL$/s/^# //g' -i /etc/sudoers
	else
		# append it
		(
			echo
			echo '## Allow members of group wheel to execute any command'
			echo '%wheel ALL=(ALL) ALL'
		) >> /etc/sudoers
	fi
	
	if [[ "$NO_DOCKER_GROUP" -ne 1 ]]; then
		# temporarily disable exiting immediately; don't care if this fails
		set +e
		groupadd docker &>/dev/null
		# re-enable exiting immediately
		set -e
		usermod -aG docker "$ADMIN_USER"
	fi
	
	(
		echo '[user]'
		echo "default=$ADMIN_USER"
		echo
	) >> /etc/wsl.conf
fi

if [[ -n "$WSL_HOSTNAME" ]]; then
	(
		echo '[network]'
		echo "hostname=$WSL_HOSTNAME"
		echo
	) >> /etc/wsl.conf
fi

if [[ "$ESSENTIAL_TOOLS" -eq 1 ]]; then
	packages=(
		reflector
		procps-ng file which
		sed gawk diffutils colordiff
		git neovim wget
		man man-db man-pages
		tar gzip zip unzip
	)
	pacman -S --noconfirm --needed "${packages[@]}"
fi

if [[ "$DEV_TOOLS" -eq 1 ]]; then
	packages=(
		gcc clang make cmake python-pip
		m4 automake
	)
	pacman -S --noconfirm --needed "${packages[@]}"
	pip install conan
fi

if [[ "$CROSS_DEV_TOOLS" -eq 1 ]]; then
	packages=(
		avr-gcc mingw-w64-gcc
	)
	pacman -S --noconfirm --needed "${packages[@]}"
fi

installed_win32yank=0
if [[ "$RUST_DEV_TOOLS" -eq 1 ]]; then
	pacman -S --noconfirm --needed rustup
	rustup install stable
	rustup default stable
	if [[ "$CROSS_DEV_TOOLS" -eq 1 ]]; then
		windows_target=x86_64-pc-windows-gnu
		rustup target add $windows_target
		if [[ "$NO_WIN32YANK" -ne 1 ]]; then
			# Build win32yank from source
			tmp_build_dir="$(mktemp -d /tmp/win32yank.XXXXXXXXXX)"
			tmp_output_dir="$tmp_build_dir/output"
			pacman -S --noconfirm --needed git
			git clone 'https://github.com/equalsraf/win32yank.git' "$tmp_build_dir"
			cargo build --manifest-path="$tmp_build_dir/Cargo.toml" --release --target $windows_target --target-dir "$tmp_output_dir"
			cp "$tmp_output_dir/x86_64-pc-windows-gnu/release/win32yank.exe" /usr/local/bin/
			rm -rf "$tmp_build_dir"
			installed_win32yank=1
		fi
	fi
fi

if [[ "$NO_WIN32YANK" -ne 1 && "$installed_win32yank" -ne 1 ]]; then
	# Use the most recent win32yank release at the time of writing
	pacman -S --noconfirm --needed wget unzip
	tmp_zip="$(mktemp /tmp/win32yank.XXXXXXXXXX)"
	wget 'https://github.com/equalsraf/win32yank/releases/download/v0.0.4/win32yank-x64.zip' -qO "$tmp_zip"
	unzip "$tmp_zip" win32yank.exe -d /usr/local/bin
	rm -f "$tmp_zip"
fi


# This will be a tmpfs, in actuality... clear out the temp files.
rm -rf /run/*

