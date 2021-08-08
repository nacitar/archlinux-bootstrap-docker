#!/usr/bin/env bash
set -e
script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="${script_path%/*}"

root_directory="/rootfs"
files_volume="/files"
output_file="${files_volume}/archlinux.tar.gz"

configure_system="${script_directory}/configure-system.sh"
arg_errors="$("${configure_system}" --argument-check "$@" 2>&1 1>/dev/null)"
if [[ -n "${arg_errors}" ]]; then
    echo "${arg_errors}" >&2
    exit 1
fi
# sanity check to ensure a clean directory
if [[ -e $root_directory ]]; then
    echo "Root directory exists, but shouldn't: ${root_directory}" >&2
    exit 1
fi

pacman -Syu --noconfirm 

mkdir "${root_directory}"
mkdir -p /run/shm  # missing from archlinux:latest but pacstrap needs it
pacstrap_config="$(mktemp)"  # pacman.conf sans any NoExtract entries
sed 's/^\s*NoExtract\s*=.*$//g' /etc/pacman.conf > "${pacstrap_config}"
pacstrap -C "${pacstrap_config}" -G "${root_directory}" base

do_configure=1
if [[ ${do_configure} -eq 1 ]]; then
    cp "${configure_system}" "${root_directory}/"
    original_resolv_conf="$(mktemp)"
    chroot_resolv_conf="${root_directory}/etc/resolv.conf"
    cp "${chroot_resolv_conf}" "${original_resolv_conf}" 
    cp /etc/resolv.conf "${chroot_resolv_conf}"
    # arch-chroot warns if the directory isn't a mount point
    mount --bind "${root_directory}" "${root_directory}"
    arch-chroot "${root_directory}" \
        /usr/bin/env bash "/${configure_system##*/}" "$@"
    umount "${root_directory}"
    cp "${original_resolv_conf}" "${chroot_resolv_conf}"
    rm -f "${root_directory}/${configure_system##*/}"
fi


"${script_directory}/create-wsl-tarball.sh" \
        --source-root="${root_directory}" \
        --destination-tarball="${output_file}" \
        --permissions-reference="${files_volume}"

