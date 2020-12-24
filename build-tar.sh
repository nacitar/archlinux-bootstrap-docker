#!/bin/bash

script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="${script_path%/*}"
error_messages=()

unhandled_flags=()
while (( $# )); do
	while [[ $1 =~ ^-[^-]{2,}$ ]]; do
		set -- ${1::-1} "-${1: -1}" "${@:2}"  # split out multiflags
	done
	case "$1" in
		-b|--base-tar) BASE_TAR=1;;
		--keep-image) KEEP_IMAGE=1;;
		--reuse-base-image) REUSE_BASE_IMAGE=1;;
		--argument-check) ARGUMENT_CHECK=1;;
		-*) unhandled_flags+=("$1");;
		*) error_messages+=("unsupported positional argument: $1");;
	esac
	shift
done
# add forced flags for the configuration script
unhandled_flags+=('--update-pacman')
unhandled_flags+=('--generate-pacman-keyring')
unhandled_flags+=('--force-setting-locale')
# allow configuration script to validate unhandled flags
child_script_argument_errors="$("$script_directory/configure-system.sh" --argument-check "${unhandled_flags[@]}" 1>/dev/null 2>&1)"
if [[ -n $child_script_argument_errors ]]; then
	error_messages+=("$child_script_argument_errors")
fi
if [[ ${#error_messages[@]} -gt 0 ]]; then
	printf "%s\n" "${error_messages[@]}" >&2
	exit 1
fi
if [[ $ARGUMENT_CHECK -eq 1 ]]; then
	exit 0
fi


if [[ $EUID -ne 0 ]]; then
	echo 'script must be run as root' >&2
	exit 1
fi

set -e  # exit upon error

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
	if [[ $export_status -ne 0 ]]; then
	       echo "error code $export_status when exporting container $container_id" >&2
	       exit 1
	fi
	if [[ $tar_status -ne 0 ]]; then
	       echo "error code $tar_status when filtering out .dockerenv from export of container $container_id" >&2
	       exit 1
	fi
	if [[ -n $SUDO_USER ]]; then
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
if [[ $REUSE_BASE_IMAGE -ne 1 ]] || ! has_docker_image "$base_wsl_image_name"; then
	if [[ -f /etc/arch-release ]]; then
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
if [[ $BASE_TAR -eq 1 ]]; then
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
	run
	--rm
	--privileged
	--mount "type=bind,src=$rootfs_directory,dst=/mnt/rootfs"
	--mount "type=bind,src=$pacstrap_script,dst=/$relative_pacstrap_script"
	"$pacstrap_base_image_name"
	"/$relative_pacstrap_script"
)
arguments=(
	build --no-cache
	--progress=plain  # so the step output isn't collapsed
	-t "$wsl_image_name"
	-f "configure-system.Dockerfile"
	"$script_directory"
	--build-arg ALL_ARGUMENTS="$(echo ${unhandled_flags[@]})"
)
docker "${arguments[@]}"
if [[ $KEEP_IMAGE -ne 1 ]]; then
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
