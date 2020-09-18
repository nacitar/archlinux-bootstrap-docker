#!/bin/bash
set -e

get_script_directory() {
	SOURCE="${BASH_SOURCE[0]}"
	while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
		DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
		SOURCE="$(readlink "$SOURCE")"
		[[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
	done
	DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
	echo "$DIR"
}

script_directory="$(get_script_directory)"

source "$script_directory/common.sh"

require_root_privilege

cleanup() {
	errored=0
	if [[ -n "$mount_point" ]]; then
		umount "$mount_point"
		if ! result_message "umount rootfs from $mount_point"; then
		       errored=1
		fi
	fi
	if [[ -n "$image_name" ]]; then
		docker image rm "$image_name"
		if ! result_message "remove temporary docker container image $image_name"; then
			errored=1
		fi
	fi
	if [[ -n "$loop_device" ]]; then
		losetup -d "$loop_device"
		if ! result_message "detach rootfs from loop device"; then
		       errored=1
		fi
	fi
	if [[ -d "$tmp_dir" ]]; then
		rm -rf "$tmp_dir"
		if ! result_message "delete temp directory and contents $tmp_dir"; then
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


get_script_directory() {
	SOURCE="${BASH_SOURCE[0]}"
	while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
		DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
		SOURCE="$(readlink "$SOURCE")"
		[[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
	done
	DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
	echo "$DIR"
}
script_directory="$(get_script_directory)"

# pacstrap needs a mount point, rather than simply a directory
# thus a loop mount is used to appease this requirement

tmp_dir="$(mktemp -d)"
result_message_or_fail 2 "create temp directory" "$tmp_dir"

rootfs="$tmp_dir/rootfs"
head -c 1G /dev/zero > "$rootfs"
result_message_or_fail 3 "create rootfs file $rootfs"

mkfs.ext4 "$rootfs"
result_message_or_fail 4 "create ext4 filesystem for temporary container"

loop_device="$(losetup -f --show "$rootfs")"
result_message_or_fail 5 "attach rootfs to loop device" "$loop_device"

image_name="arch_bootstrap:latest"
docker build --no-cache -t "$image_name" "$script_directory" 
result_message_or_fail 6 "build docker image $image_name"

docker run --rm --privileged "$image_name" "$loop_device"
result_message_or_fail 7 "run docker image $image_name"

mount_point="$tmp_dir/fsmount"
mkdir "$mount_point"  # can let the failure of the next command handle reporting
mount "$rootfs" "$mount_point"
result_message_or_fail 8 "mount rootfs to mount point $mount_point"

#init_file="$mount_point/init"
#if [[ -e "$init_file" ]]; then
#	truncate -s 0 "$init_file"
#	result_message_or_fail 9 "[WSL IMPORT BUG WORKAROUND] existing /init truncated to 0 bytes"
#else
#	touch "$init_file"
#	result_message_or_fail 10 "[WSL IMPORT BUG WORKAROUND] create missing /init as 0 byte file"
#
#	chmod 755 "$init_file"
#	result_message_or_fail 11 "[WSL IMPORT BUG WORKAROUND] set /init permissions"
#fi

tar_file="$PWD/archlinux_base_$(date "+%Y%m%d").tar"
TAR_PARAMS=(
	--selinux
	--acls
	--xattrs
	-cp
	--same-owner
	--exclude=./{dev,mnt,proc,run,sys,tmp}/*
	--exclude=./lost+found
	--one-file-system
	-C "$mount_point"
	.
)
# tar_errors="$tmp_dir/errors.log"
tar ${TAR_PARAMS[@]} > "$tar_file" # 2> "$tar_errors"
result_message_or_fail 12 "create tar file $tar_file"

if [[ -n "$SUDO_USER" ]]; then
	chown "$SUDO_USER:$SUDO_USER" $tar_file
	result_message_or_fail 13 "set tar file owner to SUDO_USER $SUDO_USER"
fi

success_message "prepared $tar_file"
