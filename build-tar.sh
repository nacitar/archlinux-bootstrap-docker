#!/bin/bash

script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="${script_path%/*}"
error_messages=()

unhandled_flags=()
while (($#)); do
  while [[ "${1}" =~ ^-[^-]{2,}$ ]]; do
    # split out multiflags
    set -- "${1::-1}" "-${1: -1}" "${@:2}"
  done
  case "${1}" in
    -k | --keep-image) KEEP_IMAGE=1 ;;
    -m | --update-mirrorlist) UPDATE_MIRRORLIST_FLAG="${1}" ;;
    --reuse-base-image) REUSE_BASE_IMAGE=1 ;;
    --temporary-working-directory=*) TEMPORARY_WORKING_DIRECTORY="${1#*=}" ;;
    --argument-check) ARGUMENT_CHECK=1 ;;
    -*) unhandled_flags+=("${1}") ;;
    *) error_messages+=("unsupported positional argument: ${1}") ;;
  esac
  shift
done
# add forced flags for the configuration script
unhandled_flags+=('--update-pacman')
unhandled_flags+=('--generate-pacman-keyring')
unhandled_flags+=('--force-setting-locale')
# allow configuration script to validate unhandled flags
child_script_argument_errors="$("${script_directory}/configure-system.sh" --argument-check "${unhandled_flags[@]}" 1>/dev/null 2>&1)"
if [[ -n "${child_script_argument_errors}" ]]; then
  error_messages+=("${child_script_argument_errors}")
fi
if [[ "${#error_messages[@]}" -gt 0 ]]; then
  printf "%s\n" "${error_messages[@]}" >&2
  exit 1
fi
if [[ "${ARGUMENT_CHECK}" -eq 1 ]]; then
  exit 0
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo 'script must be run as root' >&2
  exit 1
fi

# exit upon error
set -e

cleanup=() # function names appended to this will be called in reverse order
cleanup() {
  for ((i = ${#cleanup[@]} - 1; i >= 0; i--)); do
    "${cleanup[i]}"
  done
}
trap 'cleanup' EXIT
trap 'exit' INT

# Directory to house all script temporary work
if [[ -z "${TEMPORARY_WORKING_DIRECTORY}" ]]; then
  TEMPORARY_WORKING_DIRECTORY="$(mktemp -d)"
fi
if [[ ! -d "${TEMPORARY_WORKING_DIRECTORY}" ]]; then
  echo "Temporary working directory does not exist: ${TEMPORARY_WORKING_DIRECTORY}" >&2
  exit 1
fi
if [[ -n "$(ls -A "${TEMPORARY_WORKING_DIRECTORY}")" ]]; then
  echo "Temporary working directory is not empty: ${TEMPORARY_WORKING_DIRECTORY}" >&2
  echo 1
fi
remove_temporary_working_directory() {
  rm -rf "${TEMPORARY_WORKING_DIRECTORY}"
}
cleanup+=(remove_temporary_working_directory)

COMMON_TAR_PARAMS=(
  --xattrs --preserve-permissions --same-owner --numeric-owner
)

export_docker_container_filesystem() {
  if [[ $# -ne 2 ]]; then
    echo "Usage: export_docker_container_filesystem <container_id> <destination_tar_file>" >&2
    exit 1
  fi
  local container_id="${1}"
  local destination_tar_file="${2}"
  local repack_dir="${TEMPORARY_WORKING_DIRECTORY}/repack"
  # directory must not already exist
  mkdir "$repack_dir"
  # docker export unavoidably adds a .dockerenv, so it must be filtered out
  local UNTAR_PARAMS=(
    "${COMMON_TAR_PARAMS[@]}"
    --extract
    -C "${repack_dir}"
    --exclude=.dockerenv
  )
  local TAR_PARAMS=(
    "${COMMON_TAR_PARAMS[@]}"
    --create
    -C "${repack_dir}"
    .                      # cwd from previous line
    --transform='s,^\./,,' # remove ./
  )
  # export to the repack directory
  docker export "${container_id}" | tar "${UNTAR_PARAMS[@]}"
  if (( PIPESTATUS[0] != 0 || PIPESTATUS[1] != 0 )); then
    echo "Error when exporting container: ${container_id}" >&2
    exit 1
  fi

  # re-package to a working tar
  if ! tar "${TAR_PARAMS[@]}" >"${destination_tar_file}"; then
    echo "Error when re-packaging tar file: ${destination_tar_file}" >&2
    exit 1
  fi
  # free up now to reduce total disk overhead
  rm -rf "${repack_dir}"

  # NOTE: not sure exactly what's going on, but if I don't repackage the tar and instead do this:
  #	docker export "${container_id}" | tar --delete .dockerenv >"${destination_tar_file}"
  # If you check, hard links are messed up
  #	tar -tvf test2.tar | grep mkfs | grep "link to"
  # You'll see lines such as:
  #	hrwxr-xr-x 0/0               0 2020-09-19 13:51 usr/bin/mkfs.ext2 link to ca-certificates/extracted/cadir/Hellenic_Academic_and_Research_Institutions_ECC_RootCA_2015.pem
  # Clearly, that is NOT the correct hard link.  It seems like, without repackaging the tar,
  # doing lots of different operations on the exported tar results in corruption... not sure
  # why, but this certainly avoids it.

  # Fix permissions
  if [[ -n "${SUDO_USER}" ]]; then
    chown "${SUDO_USER}:${SUDO_USER}" "${destination_tar_file}"
  fi
}
has_docker_image() {
  docker image inspect "$@" &>/dev/null
}

base_wsl_image_name="wsl-archlinux:base"
relative_pacstrap_script=pacstrap_base_system.sh
pacstrap_script="${script_directory}/${relative_pacstrap_script}"
rootfs_directory="${TEMPORARY_WORKING_DIRECTORY}/rootfs"
mkdir "${rootfs_directory}"
# not reusing or can't because no base image exists
if [[ "${REUSE_BASE_IMAGE}" -ne 1 ]] || ! has_docker_image "${base_wsl_image_name}"; then
  if [[ -f /etc/arch-release ]]; then
    # on archlinux; can run the script directly
    # don't update the mirrorlist; don't want to change the host system
    "${pacstrap_script}" ${UPDATE_MIRRORLIST_FLAG} "${rootfs_directory}"
  else
    pacstrap_base_image_name="archlinux:latest"
    if ! has_docker_image "${pacstrap_base_image_name}"; then
      # Didn't already have the image, so if it's there after it's because of us.
      remove_pacstrap_image() {
        docker rmi -f "${pacstrap_base_image_name}"
      }
      cleanup+=(remove_pacstrap_image)
    fi

    container_rootfs_directory=/mnt/rootfs
    arguments=(
      run
      --rm
      --privileged
      --mount "type=bind,src=${rootfs_directory},dst=${container_rootfs_directory}"
      --mount "type=bind,src=${pacstrap_script},dst=/${relative_pacstrap_script}"
      "${pacstrap_base_image_name}"
      # running in a container, so update the mirror list
      "/${relative_pacstrap_script}" --update-mirrorlist "${container_rootfs_directory}"
    )
    docker "${arguments[@]}"
  fi

  FULL_SYSTEM_TAR_PARAMS=(
    "${COMMON_TAR_PARAMS[@]}"
    --create
    --exclude=./{dev,mnt,proc,run,sys,tmp}/*
    --exclude=./lost+found
    --one-file-system
    -C "${rootfs_directory}"
    . # CWD from line above
  )
  tar "${FULL_SYSTEM_TAR_PARAMS[@]}" | docker import --change "CMD /usr/bin/bash" - "${base_wsl_image_name}"
  # once it is in docker, the source directory is no longer needed
  rm -rf "${rootfs_directory}"
  if [[ "${REUSE_BASE_IMAGE}" -ne 1 ]]; then
    remove_base_docker_image() {
      docker rmi -f "${base_wsl_image_name}"
    }
    cleanup+=(remove_base_docker_image)
  fi
fi

wsl_image_name='wsl-archlinux:latest'
arguments=(
  build --no-cache
  --progress=plain # so the step output isn't collapsed
  -t "${wsl_image_name}"
  -f configure-system.Dockerfile
  "${script_directory}"
  # NOTE: spaces in unhandled_flags would cause issues here
  --build-arg ALL_ARGUMENTS="${unhandled_flags[*]}"
)
docker "${arguments[@]}"
if [[ "${KEEP_IMAGE}" -ne 1 ]]; then
  remove_docker_image() {
    docker rmi -f "${wsl_image_name}"
  }
  cleanup+=(remove_docker_image)
fi

# need to create a container in order to export the filesystem
temp_container_id="$(docker create "${wsl_image_name}")"
remove_temp_container() {
  docker rm -vf "${temp_container_id}"
}
cleanup+=(remove_temp_container)

export_docker_container_filesystem "${temp_container_id}" "${PWD}/archlinux-$(date '+%Y%m%d').tar"
