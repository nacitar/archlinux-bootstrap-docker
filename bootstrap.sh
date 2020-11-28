#!/bin/bash
set -e

if [[ "$EUID" -ne 0 ]]; then
	echo 'script must be run as root' >&2
	exit 1
fi

cleanup=()  # append function names to this, will be called in reverse order
cleanup() {
	for (( i=${#cleanup[@]}-1 ; i>=0 ; i-- )) ; do
		"${cleanup[i]}"
	done
}
trap 'cleanup' EXIT

# Arguments
loop_device="$@"
if [[ ! -b "$loop_device" ]]; then
	echo "pacstrap requires a block device but passed path is not one: $loop_device" >&2
	exit 1
fi

# the container was missing this on 9/17/2020, but it may exist later
# avoids error: "mount: /mnt/rootfs/dev/shm: mount point is a symbolic link to nowhere."
if [[ ! -d /run/shm ]]; then
	mkdir /run/shm &> /dev/null
fi

mount_point="/mnt/rootfs"
mkdir "$mount_point"

mount "$loop_device" "$mount_point"
umount_loop_device() {
	umount "$mount_point"
}
cleanup+=(umount_loop_device)

# update package db (y) and pacman
pacman -Sy --noconfirm --needed pacman
# select the 20 most recently synchronized HTTPS mirrors, sorted by download speed 
pacman -S --noconfirm --needed reflector
reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
# update the entire system
pacman -Su --noconfirm
# install the base system to the mount point
pacman -S --noconfirm --needed arch-install-scripts
pacstrap "$mount_point" base
