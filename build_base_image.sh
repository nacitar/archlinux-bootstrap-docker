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

ADMIN_USER=""
ESSENTIAL_TOOLS=0
DEV_TOOLS=0
CROSS_DEV_TOOLS=0
BASE_TAR=0
KEEP_DOCKER_IMAGE=0
REMOVE_BOOTSTRAP_IMAGE=0

#PARAMS=""
while (( "$#" )); do
	case "$1" in
		--base-tar)
			BASE_TAR=1
			shift
			;;
		--essential-tools)
			ESSENTIAL_TOOLS=1
			shift
			;;
		--dev-tools)
			DEV_TOOLS=1
			shift
			;;
		--cross-dev-tools)
			CROSS_DEV_TOOLS=1
			shift
			;;
		--keep-docker-image)
			KEEP_DOCKER_IMAGE=1
			shift
			;;
		--remove-bootstrap-image)
			REMOVE_BOOTSTRAP_IMAGE=1
			shift
			;;
		--admin-user)
			get_argument "$@"
			ADMIN_USER="$2"
			shift 2
			;;
		-*|--*=) # unsupported flags
			fail_message "Unsupported flag: $1" >&2
			exit 1
			;;
		*) # preserve positional arguments
			#PARAMS="$PARAMS $1"
			#shift
			fail_message "Unsupported positional argument: $1"
			exit 1
			;;
	esac
done
# set positional arguments in their proper place
#eval set -- "$PARAMS"

cleanup() {
	errored=0
	if [[ -n "$mount_point" ]]; then
		umount "$mount_point"
		if ! result_message "umount rootfs from $mount_point"; then
		       errored=1
		fi
	fi
	if [[ -n "$bootstrap_image_name" ]]; then
		docker image rm "$bootstrap_image_name"
		if ! result_message "remove temporary docker container image $bootstrap_image_name"; then
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

bootstrap_image_name="arch-bootstrap:latest"
bootstrap_dockerfile="arch-bootstrap.Dockerfile"
docker build --no-cache -t "$bootstrap_image_name" -f "$bootstrap_dockerfile" "$script_directory" 
result_message_or_fail 6 "build docker image $bootstrap_image_name"

docker run --rm --privileged "$bootstrap_image_name" "$loop_device"
result_message_or_fail 7 "run docker image $bootstrap_image_name"

mount_point="$tmp_dir/fsmount"
mkdir "$mount_point"  # can let the failure of the next command handle reporting
mount "$rootfs" "$mount_point"
result_message_or_fail 8 "mount rootfs to mount point $mount_point"

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
base_wsl_image_name="wsl-archlinux:base"
wsl_image_name="wsl-archlinux:latest"
run_date="$(date "+%Y%m%d")"
base_tar_file="$PWD/archlinux_base_$run_date.tar"
tar_file="$PWD/archlinux_$run_date.tar"
if (( $BASE_TAR != 0 )); then
	# just tarring up the base system; nothing else
	base_tar_file="$PWD/archlinux_base_$run_date.tar"
	# tar_errors="$tmp_dir/errors.log"
	tar ${TAR_PARAMS[@]} -C "$mount_point" . > "$base_tar_file" # 2> "$tar_errors"
	result_message_or_fail 9 "create base tar file $base_tar_file"

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

		cat "$base_tar_file" | tar ${UNTAR_PARAMS[@]} -C "$repack_dir" 
		result_message_or_fail 11 "extract tar file $base_tar_file"

		rm "$base_tar_file"
		result_message_or_fail 12 "delete tar file $base_tar_file"

		tar ${TAR_PARAMS[@]} -C "$repack_dir" . > "$base_tar_file" # 2> "$tar_errors"
		result_message_or_fail 13 "repack tarball to $base_tar_file"

		if [[ -n "$SUDO_USER" ]]; then
			chown "$SUDO_USER:$SUDO_USER" "$base_tar_file"
			result_message_or_fail 14 "set tar file owner to SUDO_USER $SUDO_USER"
		fi
	fi
	success_message "prepared $base_tar_file"
	# import the tar file we just made
	docker import "$base_tar_file" "$base_wsl_image_name"
	result_message_or_fail 15 "import base image from tar file to $base_wsl_image_name"
else
	tar ${TAR_PARAMS[@]} -C "$mount_point" . | docker import - $base_wsl_image_name
	result_message_or_fail 15 "import base image from mount point to $base_wsl_image_name"
fi
arguments=(
	build --no-cache
	-t "$wsl_image_name"
	-f "configure-system.Dockerfile"
	"$script_directory"
	--build-arg "ADMIN_USER=$ADMIN_USER"
	--build-arg "ESSENTIAL_TOOLS=$ESSENTIAL_TOOLS"
	--build-arg "DEV_TOOLS=$DEV_TOOLS"
	--build-arg "CROSS_DEV_TOOLS=$CROSS_DEV_TOOLS"
)

docker "${arguments[@]}"
result_message_or_fail 16 "build docker image $wsl_image_name"

container_name="wsl-archlinux"
docker create --name "$container_name" "$wsl_image_name"
result_message_or_fail 17 "create temporary container $container_name"

docker export "$container_name" > "$tar_file"
result_message_or_fail 18 "export container filesystem $container_name"
if [[ -n "$SUDO_USER" ]]; then
	chown "$SUDO_USER:$SUDO_USER" "$tar_file"
	result_message_or_fail 19 "set tar file owner to SUDO_USER $SUDO_USER"
fi
success_message "prepared $tar_file"

docker rm -vf "$container_name"
result_message_or_fail 20 "delete temporary container $container_name"

if [[ "$KEEP_DOCKER_IMAGE" != 1 ]]; then
	docker rmi -f "$base_wsl_image_name" "$wsl_image_name"
	result_message_or_fail 21 "delete docker images"
fi
if [[ "$REMOVE_BOOTSTRAP_IMAGE" == 1 ]]; then
	docker rmi -f "$BOOTSTRAP_IMAGE"
	result_message_or_fail 22 "delete docker bootstrap image"
fi
