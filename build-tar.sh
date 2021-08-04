#!/usr/bin/env bash
set -e
script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="${script_path%/*}"

image_name="wsl-archlinux-tarball-creator"
files_volume="${script_directory}/files"
output_file="${files_volume}/archlinux-image.tar.zip"
> "${output_file}"
docker build --rm -t "${image_name}:latest" .
docker run --privileged --mount type=bind,src="${files_volume}",dst=/files -it "${image_name}:latest" "$@"
if [[ -s ${output_file} ]]; then
    mv "${output_file}" .  # copy to user's CWD
    echo "Successfully created: ${output_file##*/}"
    #wsl --import TestArch C:\WSL\TestArch C:\WSL\archlinux-image.tar
    #wsl -d TestArch /usr/bin/env bash -c "[[ -x /apply-acls.sh ]] && /apply-acls.sh"
else
    echo "An unknown failure occurred; output file is empty: ${output_file}" 1>&2
    exit 1
fi
