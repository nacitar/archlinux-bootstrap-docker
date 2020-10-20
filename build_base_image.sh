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
	if [[ -f "$rootfs" ]]; then
		rm "$rootfs"
		if ! result_message "delete rootfs file $rootfs"; then
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

tar_file="$PWD/archlinux_base_$(date "+%Y%m%d").tar"
TAR_PARAMS=(
	--xattrs
	--preserve-permissions
	--same-owner
	--numeric-owner
	--create
	--exclude=./{dev,mnt,proc,run,sys,tmp}/*
	--exclude=./lost+found
	--one-file-system
)
# tar_errors="$tmp_dir/errors.log"
tar ${TAR_PARAMS[@]} -C "$mount_point" . > "$tar_file" # 2> "$tar_errors"
result_message_or_fail 9 "create tar file $tar_file"

# I have no idea why repacking is necessary, but this makes WSL happy...
# if you compare the tar files, with diffoscope or pkgdiff it matches.
# if you extract the tar files and use diff -qr, it matches.
# and yet, repacking _somehow_ makes WSL happy.  I blame WSL bugs
# but can't explain the nature of it.  WTF?
repack_tar=1
if (( $repack_tar != 0 )); then
	repack_dir="$tmp_dir/repack"
	mkdir "$repack_dir"
	result_message_or_fail 10 "create repack directory $repack_dir"

	UNTAR_PARAMS=(
		--xattrs
		--preserve-permissions
		--same-owner
		--numeric-owner
		--same-order
		--extract
	)

	cat "$tar_file" | tar ${UNTAR_PARAMS[@]} -C "$repack_dir" 
	result_message_or_fail 11 "extract tar file $tar_file"

	rm "$tar_file"
	result_message_or_fail 12 "delete tar file $tar_file"

	tar ${TAR_PARAMS[@]} -C "$repack_dir" . > "$tar_file" # 2> "$tar_errors"
	result_message_or_fail 13 "repack tarball to $tar_file"
fi

if [[ -n "$SUDO_USER" ]]; then
	chown "$SUDO_USER:$SUDO_USER" $tar_file
	result_message_or_fail 14 "set tar file owner to SUDO_USER $SUDO_USER"
fi

success_message "prepared $tar_file"
