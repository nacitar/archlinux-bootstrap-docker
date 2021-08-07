#!/usr/bin/env bash
set -e
script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="${script_path%/*}"

image_name="wsl-archlinux-tarball-creator"
files_volume="${script_directory}/files"
output_file="${files_volume}/archlinux.tar.gz"
docker build --rm -t "${image_name}:latest" .
docker run --rm --privileged --mount type=bind,src="${files_volume}",dst=/files -it "${image_name}:latest" "$@"
mv "${output_file}" .  # copy to user's CWD
echo ""
echo "Successfully created: ${output_file##*/}"
echo "After importing, because WSL won't let your tar file have ACLs included, in order to apply ACLs you must (assuming a DistroName of ArchLinux):"
echo -e "\twsl -d ArchLinux /usr/bin/env bash -c \"[[ -x /apply-acls.sh ]] && /apply-acls.sh\""
