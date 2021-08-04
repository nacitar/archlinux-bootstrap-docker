#!/usr/bin/env bash
set -e
script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="${script_path%/*}"

output_stem="archlinux-image"
output_file="/files/${output_stem}.tar.zip"
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
# Instead of excluding from the tar, and then having to replicate the
# same exclusions for getfacl, or filtering the output of getfacl,
# simply deleting the unwanted files.
excluded_directory_content=(dev mnt proc run sys tmp)
for directory in "${excluded_directory_content[@]}"; do
    directory="${root_directory}/${directory}"
    shopt -s nullglob dotglob
    for entry in "${directory}"/*; do
        rm -rf "${entry}"
    done
    shopt -u nullglob dotglob
done

# Store any ACLs
acl_file="$(mktemp)"
pushd "${root_directory}" &>/dev/null
getfacl --skip-base --recursive --one-file-system . > "${acl_file}"
popd &>/dev/null

if [[ -s ${acl_file} ]]; then
    cp "${acl_file}" "${root_directory}/base_system.acl"
    cp "${script_directory}/apply-acls.sh" "${root_directory}/"
fi

# tar output
TAR_ARGUMENTS=(
    --xattrs --xattrs-include="*"
    --xattrs-exclude="system.posix_acl_access"
    --xattrs-exclude="system.posix_acl_default"
    --preserve-permissions
    --numeric-owner --same-owner
    --create
    #--exclude=./{dev,mnt,proc,run,sys,tmp}/*
    #--exclude=./lost+found
    --one-file-system
    -C "${root_directory}"
    .  # CWD from previous line
    --transform='s,^\./,,'  # remove ./
)
tar_file="/${output_stem}.tar"
tar --file="${tar_file}" "${TAR_ARGUMENTS[@]}"
rm -rf "${root_directory}"
zip - "${tar_file}" > "${output_file}"
rm -f "${tar_file}"
