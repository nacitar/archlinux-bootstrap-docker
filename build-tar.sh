#!/bin/bash

# requires bash 4.2+ due to negative indexes
set -e

if [[ "$EUID" -ne 0 ]]; then
	echo 'script must be run as root' >&2
	exit 1
fi

script_directory="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"

while (( "$#" )); do
	while [[ "$1" =~ ^-[^-]{2,}$ ]]; do
		set -- ${1::-1} "-${1: -1}" "${@:2}"  # split out multiflags
	done
	case "$1" in
		-b|--base-tar) BASE_TAR=1;;
		-e|--essential-tools) ESSENTIAL_TOOLS=1;;
		-d|--dev-tools) DEV_TOOLS=1;;
		-r|--rust-dev-tools) RUST_DEV_TOOLS=1;;
		-c|--cross-dev-tools) CROSS_DEV_TOOLS=1;;
		--no-win32yank) NO_WIN32YANK=1;;
		--admin-user=*) ADMIN_USER=${1#*=};;
		--wsl-hostname=*) WSL_HOSTNAME=${1#*=};;
		--keep-image) KEEP_IMAGE=1;;
		--reuse-base-image) REUSE_BASE_IMAGE=1;;
		--no-docker-group) NO_DOCKER_GROUP=1;;
		-*) echo "unsupported flag: $1" >&2; exit 1;;
		*) echo "unsupported positional argument: $1" >&2; exit 1;;
	esac
	shift
done

cleanup=()  # function names appended to this will be called in reverse order
cleanup() {
	for (( i=${#cleanup[@]}-1 ; i>=0 ; i-- )) ; do
		"${cleanup[i]}"
	done
}
trap 'cleanup' EXIT
trap 'exit' INT

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
has_docker_image() {
	docker image inspect "$@" &>/dev/null
}

# pacstrap needs a mount point, rather than simply a directory
# thus a loop mount is used to appease this requirement
tmp_dir="$(mktemp -d)"
remove_tmp_dir() {
	rm -rf "$tmp_dir"
}
cleanup+=(remove_tmp_dir)

base_wsl_image_name="wsl-archlinux:base"
relative_pacstrap_script="pacstrap_base_system.sh"
pacstrap_script="$script_directory/$relative_pacstrap_script"
# not reusing or can't because no base image exists
if [[ "$REUSE_BASE_IMAGE" -ne 1 ]] || ! has_docker_image "$base_wsl_image_name"; then
	if [ -f /etc/arch-release ]; then
		# on archlinux; can run the script directly 
		"$pacstrap_script"
	else
		pacstrap_base_image_name="archlinux:latest"
		if ! has_docker_image "$pacstrap_base_image_name"; then
			# Didn't already have the image, so if it's there after it's because of us.
			remove_pacstrap_image() {
				docker rmi -f "$pacstrap_base_image_name"
			}
			cleanup+=(remove_pacstrap_image)
		fi

		rootfs_directory="$tmp_dir/rootfs"
		arguments=(
			run
			--rm
			--privileged
			--mount "type=bind,src=$rootfs_directory,dst=/mnt/rootfs"
			--mount "type=bind,src=$pacstrap_script,dst=/$relative_pacstrap_script"
			"$pacstrap_base_image_name"
			"/$relative_pacstrap_script"
		)
		docker "${arguments[@]}"
	fi

	TAR_PARAMS=(
		--xattrs
		--preserve-permissions
		--same-owner
		--numeric-owner
		--create
		--exclude=./{dev,mnt,proc,run,sys,tmp}/*
		--exclude=./lost+found
		--one-file-system
		-C "$rootfs_directory"
		.  # CWD from line above
	)
	tar "${TAR_PARAMS[@]}" | docker import --change "ENTRYPOINT [ \"bash\" ]" - $base_wsl_image_name
	if [[ "$REUSE_BASE_IMAGE" -ne 1 ]]; then
		remove_base_docker_image() {
			docker rmi -f "$base_wsl_image_name"
		}
		cleanup+=(remove_base_docker_image)
	fi
fi

run_date="$(date "+%Y%m%d")"
if [[ "$BASE_TAR" -eq 1 ]]; then
	# need to create a container in order to export the filesystem
	temp_base_container_id="$(docker create "$base_wsl_image_name")"
	remove_temp_base_container() {
		docker rm -vf "$temp_base_container_id"
	}
	cleanup+=(remove_temp_base_container)
	export_docker_container_filesystem "$temp_base_container_id" "$PWD/archlinux-base-$run_date.tar"
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
	--build-arg "NO_DOCKER_GROUP=$NO_DOCKER_GROUP"
	--build-arg "WSL_HOSTNAME=$WSL_HOSTNAME"
	--build-arg "ESSENTIAL_TOOLS=$ESSENTIAL_TOOLS"
	--build-arg "DEV_TOOLS=$DEV_TOOLS"
	--build-arg "RUST_DEV_TOOLS=$RUST_DEV_TOOLS"
	--build-arg "CROSS_DEV_TOOLS=$CROSS_DEV_TOOLS"
	--build-arg "NO_WIN32YANK=$NO_WIN32YANK"
)
docker "${arguments[@]}"
if [[ "$KEEP_IMAGE" -ne 1 ]]; then
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
export_docker_container_filesystem "$temp_container_id" "$PWD/archlinux-$run_date.tar"
