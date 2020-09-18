#!/bin/bash
set -e

source "/common.sh"

require_root_privilege

cleanup() {
	errored=0
	if [[ -n "$mount_point" ]]; then
		umount "$mount_point"
		if ! result_message "umount rootfs from $mount_point"; then
		       errored=1
		fi
	fi
	if (( $errored != 0 )); then
		fail_message "cleanup had errors"
	else
		success_message "cleanup complete"
	fi
	return $errored
}
trap 'cleanup' EXIT


loop_device="$@"
if [[ ! -b "$loop_device" ]]; then
	fail 2 "passed path is not a block device \"$loop_device\""
fi

# the container was missing this on 9/17/2020, but it may exist later
# avoids error: "mount: /mnt/rootfs/dev/shm: mount point is a symbolic link to nowhere."
mkdir /run/shm &> /dev/null
if [[ ! -d /run/shm ]]; then
	fail 3 "/run/shm is missing or not a directory"
fi

mount_point="/mnt/rootfs"
mkdir "$mount_point"
result_message_or_fail 4 "create mount point $mount_point"

mount "$loop_device" "$mount_point"
result_message_or_fail 5 "mount passed loop device \"$loop_device\" to \"$mount_point\""

pacman --noconfirm -Sy reflector
result_message_or_fail 6 "install reflector"

mirror_check_count=20
reflector --latest "$mirror_check_count" --protocol https --sort rate --save /etc/pacman.d/mirrorlist
result_message_or_fail 7 "select fastest of the $mirror_check_count most recently updated mirrors"

pacman --noconfirm -Syu arch-install-scripts
result_message_or_fail 8 "update system and install arch-install-scripts"

pacstrap "$mount_point" base
result_message_or_fail 9 "bootstrap rootfs $mount_point" 
