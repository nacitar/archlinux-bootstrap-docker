#!/bin/bash
set -e

if (( $EUID != 0 )); then
	echo 'script must be run as root' >&2
	exit 1
fi

script_directory="$(dirname "${BASH_SOURCE[0]}")"

ADMIN_USER=""
ESSENTIAL_TOOLS=0
DEV_TOOLS=0
CROSS_DEV_TOOLS=0
BASE_TAR=0
KEEP_DOCKER_IMAGE=0
FROM_EXISTING_BASE=0
REMOVE_BOOTSTRAP_BASE_IMAGE=0

check_argument() {
	if [ -z $2 ] || [ ${2:0:1} == "-" ]; then
		# no next argument or next argument is another flag
		echo "Expected argument for option: $1. None received, exiting." >&2
		exit 1
	fi
}
while (( "$#" )); do
	case "$1" in
		--base-tar) BASE_TAR=1;	shift;;
		--essential-tools) ESSENTIAL_TOOLS=1; shift;;
		--dev-tools) DEV_TOOLS=1; shift;;
		--cross-dev-tools) CROSS_DEV_TOOLS=1; shift;;
		--keep-docker-image) KEEP_DOCKER_IMAGE=1; shift;;
		--from-existing-base)
			FROM_EXISTING_BASE=1
			KEEP_DOCKER_IMAGE=1  # forced
			shift;;
		--remove-bootstrap-base-image) REMOVE_BOOTSTRAP_BASE_IMAGE=1; shift;;
		--admin-user) check_argument "$@"; ADMIN_USER="$2"; shift 2;;
		-*|--*=)
			echo "Unsupported flag: $1" >&2
			exit 1
			;;
		*)
			echo "Unsupported positional argument: $1" >&2
			exit 1
			;;
	esac
done

cleanup() {
	echo "Cleaning up..."
	if [[ "$KEEP_DOCKER_IMAGE" != 1 ]]; then
		if [[ -n "$wsl_image_name" ]]; then
			docker rmi -f "$wsl_image_name"
		fi
		if [[ -n "$base_wsl_image_name" ]]; then
			docker rmi -f "$base_wsl_image_name"
		fi
	fi
	if [[ -n "$mount_point" ]]; then
		umount "$mount_point"
	fi
	if [[ -n "$bootstrap_image_name" ]]; then
		docker image rm "$bootstrap_image_name"
	fi
	if [[ "$REMOVE_BOOTSTRAP_BASE_IMAGE" == 1 ]]; then
		if [[ -n "$bootstrap_base_image_name" ]]; then
			docker rmi -f "$bootstrap_base_image_name"
		fi
	fi
	if [[ -n "$loop_device" ]]; then
		losetup -d "$loop_device"
	fi
	if [[ -f "$rootfs" ]]; then
		rm "$rootfs"
	fi
	if [[ -d "$tmp_dir" ]]; then
		rm -rf "$tmp_dir"
	fi
}
trap 'cleanup' EXIT

export_docker_image() {
	if [[ $# -ne 2 ]]; then
		echo "Usage: export_docker_image <image_name> <destination_tar_file>"
	fi
	set -e  # hack.. never do this if it might be called interactively
	image_name="$1"
	tar_file="$2"
	# create temporary container
	container_id="$(docker create "$image_name")"
	# docker export unavoidably adds a .dockerenv, so it must be filtered out
	docker export "$container_id" | tar --delete .dockerenv > "$tar_file"
	if [[ -n "$SUDO_USER" ]]; then
		chown "$SUDO_USER:$SUDO_USER" "$tar_file"
	fi
	# delete temporary container
	docker rm -vf "$container_id"
}
# pacstrap needs a mount point, rather than simply a directory
# thus a loop mount is used to appease this requirement
tmp_dir="$(mktemp -d)"

if (( $FROM_EXISTING_BASE == 0 )); then
	# only needs enough space for the base pacstrap
	rootfs="$tmp_dir/rootfs"
	head -c 1G /dev/zero > "$rootfs"
	mkfs.ext4 "$rootfs"

	loop_device="$(losetup -f --show "$rootfs")"

	bootstrap_base_image_name="archlinux:latest"
	bootstrap_image_name="arch-bootstrap:latest"
	docker build --no-cache -t "$bootstrap_image_name" -f arch-bootstrap.Dockerfile "$script_directory" 

	docker run --rm --privileged "$bootstrap_image_name" "$loop_device"

	mount_point="$tmp_dir/fsmount"
	mkdir "$mount_point"  # can let the failure of the next command handle reporting
	mount "$rootfs" "$mount_point"

	base_wsl_image_name="wsl-archlinux:base"
	TAR_PARAMS=(
		--xattrs
		--preserve-permissions
		--same-owner
		--numeric-owner
		--create
		--exclude=./{dev,mnt,proc,run,sys,tmp}/*
		--exclude=./lost+found
		--one-file-system
		-C "$mount_point"
		.  # CWD from line above
	)
	tar ${TAR_PARAMS[@]} | docker import --change "ENTRYPOINT [ \"bash\" ]" - $base_wsl_image_name
else
	base_wsl_image_name="wsl-archlinux:base"
fi

run_date="$(date "+%Y%m%d")"
if (( $BASE_TAR != 0 )); then
	export_docker_image "$base_wsl_image_name" "$PWD/archlinux_base_$run_date.tar"
fi

wsl_image_name="wsl-archlinux:latest"
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

# need to create a container in order to export the filesystem
export_docker_image "$wsl_image_name" "$PWD/archlinux_$run_date.tar"

exit 0
