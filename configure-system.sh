#!/bin/bash
set -e

if (( $EUID != 0 )); then
	echo 'script must be run as root' >&2
	exit 1
fi

# FROM ENVIRONMENT
# - ADMIN_USER
# - ESSENTIAL_TOOLS
# - DEV_TOOLS
# - CROSS_DEV_TOOLS

DEFAULT_PASSWORD="archlinux"

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
	pacman -Syu --noconfirm sudo shadow  # shadow is for chpasswd

	(
		echo
		echo '## Allow members of group wheel to execute any command'
		echo '%wheel ALL=(ALL) ALL'
	) >> /etc/sudoers

	(
		echo '[user]'
		echo "default=$ADMIN_USER"
	) > /etc/wsl.conf
fi

if [[ "$ESSENTIAL_TOOLS" == 1 ]]; then
	packages=(
		procps-ng file which
		sed gawk
		neovim
		man man-db man-pages
		tar gzip zip unzip
	)
	pacman -Syu --noconfirm "${packages[@]}"
fi

if [[ "$DEV_TOOLS" == 1 ]]; then
	packages=(
		git gcc clang
		make cmake
		python-pip
	)
	pacman -Syu --noconfirm "${packages[@]}"
	pip install conan
fi

if [[ "$CROSS_DEV_TOOLS" == 1 ]]; then
	packages=(
		avr-gcc mingw-w64-gcc
	)
	pacman -Syu --noconfirm "${packages[@]}"
fi

# TODO: remove excess files now, or later.. and avoid reinstalling packages

