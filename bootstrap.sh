#!/bin/bash
set -e

if (( $EUID != 0 )); then
	echo 'script must be run as root' >&2
	exit 1
fi

cleanup() {
	echo "Cleaning up..."
	if [[ -n "$mount_point" ]]; then
		umount "$mount_point"
	fi
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

pacman --noconfirm -Sy reflector

mirror_check_count=20
reflector --latest "$mirror_check_count" --protocol https --sort rate --save /etc/pacman.d/mirrorlist

pacman --noconfirm -Syu arch-install-scripts

pacstrap "$mount_point" base
