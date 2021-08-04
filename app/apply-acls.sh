#!/usr/bin/env bash

set -e

script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="${script_path%/*}"

cd /
acl_file="base_system.acl"
if [[ -s ${acl_file} ]]; then
    echo "Setting acls from ${acl_file}"
    setfacl --restore="${acl_file}"
    rm "${acl_file}"
    if [[ -z "${script_directory}" ]]; then
        # running from /
        echo "Removing ${script_path}"
        rm "${script_path}"
    fi
fi
