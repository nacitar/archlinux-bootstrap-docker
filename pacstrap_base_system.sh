#!/bin/bash
set -e

if [[ "${EUID}" -ne 0 ]]; then
  echo 'script must be run as root' >&2
  exit 1
fi
trap 'exit' INT

rootfs_directory="$*"
if [[ -z "${rootfs_directory}" ]]; then
  rootfs_directory=/mnt/rootfs
fi
if [[ ! -d "${rootfs_directory}" ]]; then
  echo "root directory does not exist: ${rootfs_directory}" >&2
  exit 1
fi

# the container was missing this on 9/17/2020, but it may exist later
# avoids error: "mount: /mnt/rootfs/dev/shm: mount point is a symbolic link to nowhere."
if [[ ! -d /run/shm ]]; then
  mkdir /run/shm &>/dev/null
fi

echo ''
echo 'Updating package db and pacman itself...'
pacman -Sy --noconfirm --needed pacman
echo ''
echo 'Installing reflector...  Likely to be slow as the mirror list has not yet been updated...'
pacman -S --noconfirm --needed reflector
echo ''
echo 'Using reflector to generate an optimal mirror list...  Messages about timeouts are normal.'
# select the 20 most recently synchronized HTTPS mirrors, sorted by download speed; these will be copied by pacstrap
reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
echo ''
echo 'Installing pacstrap...'
pacman -S --noconfirm --needed arch-install-scripts
echo ''
echo 'Running pacstrap (without copying pacman keyring)...'
pacstrap -G "${rootfs_directory}" base
