#!/usr/bin/env bash
set -e
script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="${script_path%/*}"

output_file="/files/archlinux-image.tar.gz"
if [[ ! -f ${output_file} ]]; then
    echo "Must mount a volume with existing file: ${output_file}" >&2
    exit 1
fi
root_directory="/rootfs"
if [[ -e $root_directory ]]; then
    echo "Root directory exists, but shouldn't: ${root_directory}" >&2
    exit 1
fi
configure_system="${script_directory}/configure-system.sh"
arg_errors="$("${configure_system}" --argument-check "$@" 2>&1 1>/dev/null)"
if [[ -n "${arg_errors}" ]]; then
    echo "${arg_errors}" >&2
    exit 1
fi

true > "${output_file}"  # clear any pre-existing output
mkdir "${root_directory}"
pacman -Syu --noconfirm 

mkdir -p /run/shm  # missing from archlinux:latest but pacstrap needs it
pacstrap_config="$(mktemp)"  # pacman.conf sans any NoExtract entries
sed 's/^\s*NoExtract\s*=.*$//g' /etc/pacman.conf > "${pacstrap_config}"
pacstrap -C "${pacstrap_config}" -G "${root_directory}" base

app_directory="${root_directory}/app"
mkdir "${app_directory}"
cp "${configure_system}" "${app_directory}/"

original_resolv_conf="$(mktemp)"
chroot_resolv_conf="${root_directory}/etc/resolv.conf"
cp "${chroot_resolv_conf}" "${original_resolv_conf}" 
cp /etc/resolv.conf "${chroot_resolv_conf}"
# arch-chroot warns if the directory isn't a mount point
mount --bind "${root_directory}" "${root_directory}"
arch-chroot "${root_directory}" \
    /usr/bin/env bash "/app/${configure_system##*/}" "$@"
umount "${root_directory}"
cp "${original_resolv_conf}" "${chroot_resolv_conf}"

TAR_ARGUMENTS=(
    --xattrs --xattrs-include="*" --preserve-permissions
    --numeric-owner --same-owner
    --create
    --exclude=./{dev,mnt,proc,run,sys,tmp}/*
    --exclude=./lost+found,./app
    --one-file-system
    --gzip
    -C "${root_directory}"
    .  # CWD from previous line
    --transform='s,^\./,,'  # remove ./
)
tar --file="${output_file}" "${TAR_ARGUMENTS[@]}" 
