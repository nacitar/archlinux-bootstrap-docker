#!/usr/bin/env bash
set -e

cleanup=() # function names appended to this will be called in reverse order
cleanup() {
  for ((i = ${#cleanup[@]} - 1; i >= 0; i--)); do
    "${cleanup[i]}"
  done
}
trap 'cleanup' EXIT
trap 'exit' INT

temporary_working_directory="$(mktemp -d)"
repack_dir="${temporary_working_directory}/repack"
mkdir "$repack_dir"
remove_temp_directory() {
    rm -rf "${temporary_working_directory}"
}
cleanup+=(remove_temp_directory)

COMMON_TAR_PARAMS=(
  --xattrs --xattrs-include='*' --preserve-permissions --same-owner --numeric-owner
)
UNTAR_PARAMS=(
    "${COMMON_TAR_PARAMS[@]}"
    --extract
    -C "${repack_dir}"
    --exclude=.dockerenv
)
TAR_PARAMS=(
    "${COMMON_TAR_PARAMS[@]}"
    --create
    -C "${repack_dir}"
    .                      # cwd from previous line
    --transform='s,^\./,,' # remove ./
)
output_file="${1}.re.tar"
if [[ -e ${output_file} ]]; then
    rm -f "${output_file}"
fi
# export to the repack directory
tar --file="${1}" "${UNTAR_PARAMS[@]}"
#true > "${repack_dir}/etc/hostname"
#true > "${repack_dir}/etc/hosts"
true > "${repack_dir}/etc/resolv.conf"
tar --file="${output_file}" "${TAR_PARAMS[@]}"
if [[ -n $SUDO_USER ]]; then
    chown "$SUDO_USER:$SUDO_USER" "${output_file}"
fi
