#!/usr/bin/env bash
set -e
script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="${script_path%/*}"

error_messages=()
while (($#)); do
    while [[ "${1}" =~ ^-[^-]{2,}$ ]]; do
        set -- "${1::-1}" "-${1: -1}" "${@:2}"  # split multiflags
    done
    case "${1}" in
        --source-root=*) SOURCE_ROOT="${1#*=}" ;;
        --destination-tarball=*) DESTINATION_TARBALL="${1#*=}" ;;
        --argument-check) ARGUMENT_CHECK=1 ;;
        --permissions-reference=*) PERMISSIONS_REFERENCE="${1#*=}" ;;
        -*) error_messages+=("unsupported flag: ${1}") ;;
        *) error_messages+=("unsupported positional argument: ${1}") ;;
    esac
    shift
done

if [[ -z "${SOURCE_ROOT}" ]]; then
    error_messages+=("No source root specified.")
fi
if [[ -z "${DESTINATION_TARBALL}" ]]; then
    error_messages+=("No destination tarball specified.")
fi
if [[ -z "${PERMISSIONS_REFERENCE}" ]]; then
    error_messages+=("No permissions reference specified.")
else
    if [[ ! -e "${PERMISSIONS_REFERENCE}" ]]; then
        error_messages+=("Reference file does not exist: ${PERMISSIONS_REFERENCE}")
    fi
fi
if [[ ${#error_messages[@]} -gt 0 ]]; then
  printf "%s\n" "${error_messages[@]}" >&2
  exit 1
fi
if [[ "${ARGUMENT_CHECK}" -eq 1 ]]; then
  exit 0
fi

excluded_directory_content=(dev mnt proc run sys tmp)
# Instead of excluding from the tar, and then having to replicate the
# same exclusions for getfacl, or filtering the output of getfacl,
# simply deleting the unwanted files.
for directory in "${excluded_directory_content[@]}"; do
    directory="${SOURCE_ROOT}/${directory}"
    shopt -s nullglob dotglob
    for entry in "${directory}"/*; do
        rm -rf "${entry}"
    done
    shopt -u nullglob dotglob
done
# Delete sockets; they are rightly ignored by tar, and unfortunately this
# check breaks --remove-files, by leaving files in directories it tries to
# later delete.
find "${SOURCE_ROOT}" -type s -exec rm -f {} \;

# Store any ACLs
acl_file="$(mktemp)"
pushd "${SOURCE_ROOT}" &>/dev/null
getfacl --skip-base --recursive --one-file-system . > "${acl_file}"
popd &>/dev/null

if [[ -s ${acl_file} ]]; then
    cp "${acl_file}" "${SOURCE_ROOT}/system.acl"
    cp "${script_directory}/apply-acls.sh" "${SOURCE_ROOT}/"
fi

TAR_ARGUMENTS=(
    --xattrs --xattrs-include="*"
    --xattrs-exclude="system.posix_acl_access"
    --xattrs-exclude="system.posix_acl_default"
    --preserve-permissions
    --numeric-owner --same-owner
    --create
    --one-file-system
    --transform='s,^\./,,'  # remove ./
    --remove-files
)
echo "Creating tarball: ${DESTINATION_TARBALL}"
# write file with permissions in place, using
# the same owner as PERMISSIONS_REFERENCE
install -m 644 $(stat -c "-o %u -g %g" "${PERMISSIONS_REFERENCE}") \
    <(tar "${TAR_ARGUMENTS[@]}" -C "${SOURCE_ROOT}" . | gzip) \
    "${DESTINATION_TARBALL}"
rm -rf "${SOURCE_ROOT}"
