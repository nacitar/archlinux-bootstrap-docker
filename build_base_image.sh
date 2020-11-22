#!/bin/bash

# requires bash 4.2+ due to negative indexes
set -e

if [[ "$EUID" -ne 0 ]]; then
	echo 'script must be run as root' >&2
	exit 1
fi

script_directory="$(dirname "${BASH_SOURCE[0]}")"

while (( "$#" )); do
	while [[ "$1" == -[^-][^-]* ]]; do
		set -- ${1::-1} "-${1: -1}" "${@:2}"  # split out multiflags
	done
	case "$1" in
		-b|--base-tar) BASE_TAR=1;;
		-e|--essential-tools) ESSENTIAL_TOOLS=1;;
		-d|--dev-tools) DEV_TOOLS=1;;
		-c|--cross-dev-tools) CROSS_DEV_TOOLS=1;;
		-r|--remove-bootstrap-base-image) REMOVE_BOOTSTRAP_BASE_IMAGE=1;;
		--keep-base-docker-image) KEEP_BASE_DOCKER_IMAGE=1;;
		--keep-docker-image) KEEP_DOCKER_IMAGE=1;;
		--from-existing-base) FROM_EXISTING_BASE=1;;
		--admin-user=*) ADMIN_USER=${1#*=};;
		-*) echo "unsupported flag: $1" >&2; exit 1;;
		*) echo "unsupported positional argument: $1" >&2; exit 1;;
	esac
	shift
done

cleanup=()  # append function names to this, will be called in reverse order
cleanup() {
	for (( i=${#cleanup[@]}-1 ; i>=0 ; i-- )) ; do
		"${cleanup[i]}"
	done
}
trap 'cleanup' EXIT

export_docker_container_filesystem() {
	if [[ $# -ne 2 ]]; then
		echo "Usage: export_docker_container_filesystem <container_id> <destination_tar_file>"
	fi
	container_id="$1"
	destination_tar_file="$2"
	# docker export unavoidably adds a .dockerenv, so it must be filtered out
	docker export "$container_id" | tar --delete .dockerenv > "$destination_tar_file"
	export_status="${PIPESTATUS[0]}" tar_status="${PIPESTATUS[0]}"
	if [[ "$export_status" -ne 0 ]]; then
	       echo "error code $export_status when exporting container $container_id" >&2
	       exit 1
	fi
	if [[ "$tar_status" -ne 0 ]]; then
	       echo "error code $tar_status when filtering out .dockerenv from export of container $container_id" >&2
	       exit 1
	fi
	if [[ -n "$SUDO_USER" ]]; then
		chown "$SUDO_USER:$SUDO_USER" "$destination_tar_file"
	fi
}

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
remove_tmp_dir() {
	rm -rf "$tmp_dir"
}
cleanup+=(remove_tmp_dir)

if [[ "$FROM_EXISTING_BASE" -ne 1 ]]; then
	# only needs enough space for the base pacstrap
	rootfs="$tmp_dir/rootfs"
	head -c 1G /dev/zero > "$rootfs"
	remove_rootfs() {
		rm "$rootfs"
	}
	cleanup+=(remove_rootfs)

	mkfs.ext4 "$rootfs"

	loop_device="$(losetup -f --show "$rootfs")"
	detach_loop_device() {
		losetup -d "$loop_device"
	}
	cleanup+=(detach_loop_device)

	bootstrap_base_image_name="archlinux:latest"
	bootstrap_image_name="arch-bootstrap:latest"
	docker build --no-cache -t "$bootstrap_image_name" -f arch-bootstrap.Dockerfile "$script_directory" 
	remove_bootstrap_image() {
		docker rmi "$bootstrap_image_name"
		if [[ "$REMOVE_BOOTSTRAP_BASE_IMAGE" -eq 1 ]]; then
			docker rmi -f "$bootstrap_base_image_name"
		fi
	}
	cleanup+=(remove_bootstrap_image)

	docker run --rm --privileged "$bootstrap_image_name" "$loop_device"

	mount_point="$tmp_dir/fsmount"
	mkdir "$mount_point"  # can let the failure of the next command handle reporting
	mount "$rootfs" "$mount_point"
	umount_rootfs() {
		umount "$mount_point"
	}
	cleanup+=(umount_rootfs)

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
	if [[ $KEEP_BASE_DOCKER_IMAGE -ne 1 ]]; then
		remove_base_docker_image() {
			docker rmi -f "$base_wsl_image_name"
		}
		cleanup+=(remove_base_docker_image)
	fi
else
	base_wsl_image_name="wsl-archlinux:base"
fi

run_date="$(date "+%Y%m%d")"
if [[ "$BASE_TAR" -ne 0 ]]; then
	# need to create a container in order to export the filesystem
	temp_base_container_id="$(docker create "$base_wsl_image_name")"
	remove_temp_base_container() {
		docker rm -vf "$temp_base_container_id"
	}
	cleanup+=(remove_temp_base_container)
	export_docker_container_filesystem "$temp_base_container_id" "$PWD/archlinux_base_$run_date.tar"
	unset cleanup[-1]  # if no throws yet, remove it early to free space
	remove_temp_base_container
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
if [[ $KEEP_DOCKER_IMAGE -ne 1 ]]; then
	remove_docker_image() {
		docker rmi -f "$wsl_image_name"
	}
	cleanup+=(remove_docker_image)
fi

# need to create a container in order to export the filesystem
temp_container_id="$(docker create "$wsl_image_name")"
remove_temp_container() {
	docker rm -vf "$temp_container_id"
}
cleanup+=(remove_temp_container)
export_docker_container_filesystem "$temp_container_id" "$PWD/archlinux_$run_date.tar"

exit 0
