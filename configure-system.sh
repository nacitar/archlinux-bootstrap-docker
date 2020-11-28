#!/bin/bash
set -e

if [[ "$EUID" -ne 0 ]]; then
	echo 'script must be run as root' >&2
	exit 1
fi

# FROM ENVIRONMENT
# - ADMIN_USER
# - ESSENTIAL_TOOLS
# - DEV_TOOLS
# - CROSS_DEV_TOOLS

DEFAULT_PASSWORD="archlinux"

# update package db (y) and pacman
pacman -Sy --noconfirm --needed pacman
# select the 20 most recently synchronized HTTPS mirrors, sorted by download speed 
pacman -S --noconfirm --needed reflector
reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
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

	(
		echo '[user]'
		echo "default=$ADMIN_USER"
	) > /etc/wsl.conf
fi

if [[ "$ESSENTIAL_TOOLS" -eq 1 ]]; then
	packages=(
		procps-ng file which
		sed gawk
		neovim
		man man-db man-pages
		tar gzip zip unzip
	)
	pacman -S --noconfirm --needed "${packages[@]}"
fi

if [[ "$DEV_TOOLS" -eq 1 ]]; then
	packages=(
		git gcc clang
		make cmake
		python-pip
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

# This will be a tmpfs, in actuality... clear out the temp files.
rm -rf /run/*

