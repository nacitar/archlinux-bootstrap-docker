#!/bin/bash

error_messages=()

while (($#)); do
  while [[ "${1}" =~ ^-[^-]{2,}$ ]]; do
    set -- "${1::-1}" "-${1: -1}" "${@:2}"  # split multiflags
  done
  case "${1}" in
    -d | --dev-tools) DEV_TOOLS=1 ;;
    -r | --rust-dev-tools) RUST_DEV_TOOLS=1 ;;
    -c | --cross-dev-tools) CROSS_DEV_TOOLS=1 ;;
    # if specified with RUST_DEV_TOOLS and CROSS_DEV_TOOLS, builds from source
    -y | --win32yank) WIN32YANK=1 ;;
    --wsl-ns-bashrc) WSL_NS_BASHRC=1 ;;
    --wsl-ns-neovim-config) WSL_NS_NEOVIM_CONFIG=1 ;;
    --wsl-ns-all)
      arguments=(
        --wsl-docker
        --wsl-ns-bashrc
        --wsl-ns-neovim-config
      )
      set -- "${arguments[@]}" "${@:2}"
      continue
      ;;
    -*) error_messages+=("unsupported flag: ${1}") ;;
    *) error_messages+=("unsupported positional argument: ${1}") ;;
  esac
  shift
done

if [[ ${#error_messages[@]} -gt 0 ]]; then
  printf "%s\n" "${error_messages[@]}" >&2
  exit 1
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

# update package db (y) and pacman
pacman -Sy --noconfirm --needed pacman

# Virtually any python project will leave you wanting a virtualenv
python -m pip install virtualenv

packages=(
  base-devel
  man-pages
  keychain openssh wget lsof
  diffutils colordiff
  zip unzip
  git
  neovim
)
pacman -S --noconfirm --needed "${packages[@]}"

AUR_CONFIG_FILE='/etc/pacman.d/aur'
tmp_build_dir="$(mktemp -d '/tmp/aurutils.XXXXXXXXXX')"
remove_tmp_build_dir() {
	if [[ -e "${tmp_build_dir}" ]]; then
		rm -rf "${tmp_build_dir}"
	fi
}
cleanup+=(remove_tmp_build_dir)
git clone 'https://aur.archlinux.org/aurutils.git' "${tmp_build_dir}"
pushd "${tmp_build_dir}"
# makepkg cannot be ran as root, so 'nobody' will be used
# and it needs access to the directory.
chown -R nobody:nobody .
NOBODY_SUDOERS_FILE='/etc/sudoers.d/nobody_pacman'
echo "nobody ALL=(ALL) NOPASSWD: /usr/sbin/pacman" > "${NOBODY_SUDOERS_FILE}"
remove_nobody_sudoers_file() {
	if [[ -e "${NOBODY_SUDOERS_FILE}" ]]; then
		rm "${NOBODY_SUDOERS_FILE}"
	fi
}
cleanup+=(remove_nobody_sudoers_file)
su -s /bin/bash nobody -c "makepkg -s --noconfirm"
remove_nobody_sudoers_file  # early cleanup
package_file=(aurutils-*.pkg.tar.zst)
if [[ "${#package_file[@]}" -ne 1 ]]; then
	echo "Expected exactly one package, but found ${#package_file[@]}: ${package_file[*]}" >&2
	exit 1
fi
# create the cache directory and give wheel access
AUR_CACHE_DIRECTORY='/var/cache/pacman/aur'
destination_package_file="${AUR_CACHE_DIRECTORY}/${package_file[0]}"
install -d -m 0775 -o root -g wheel "${AUR_CACHE_DIRECTORY}"
# Make new files inherit the group owner of the cache directory
# aur sync will write packages without the group, though,
# making it so all wheel users can add packages and use them,
# but users can't remove packages others built.
chmod g+s "${AUR_CACHE_DIRECTORY}"
# Set the default group permissions for newly created
# files to rw and and directories rwx.
setfacl -d -m g::rwX "${AUR_CACHE_DIRECTORY}"
# Copy over the package file
install -m 0664 -o root -g wheel "${package_file[0]}" "${destination_package_file}"
popd
remove_tmp_build_dir  # early cleanup
repo-add "${AUR_CACHE_DIRECTORY}/aur.db.tar.bz2" "$destination_package_file"
# configure pacman
cat <<EOF >"$AUR_CONFIG_FILE"
[options]
# use the original CacheDir, but allow falling back to the AUR dir.
CacheDir = /var/cache/pacman/pkg
CacheDir = /var/cache/pacman/aur
CleanMethod = KeepCurrent

[aur]
SigLevel = Optional TrustAll
Server = file://${AUR_CACHE_DIRECTORY}
EOF
include_line="Include = ${AUR_CONFIG_FILE}"
# make sure the line isn't already present
if ! grep -q ^"${include_line}"$ /etc/pacman.conf; then
	# escape the forward slashes in the config path
	aur_comment="# AUR support:  aurutils uses the first file:\\/\\/ scheme Server entry."
	sed "s/^\\s*\\[options\\]\\s*$/\n${aur_comment}\n${include_line//\//\\/}\n[options]/" -i /etc/pacman.conf
fi
pacman -Sy
# aurutils uses vifm for previewing files
pacman -S --noconfirm --needed aurutils vifm
# whenever vifm is opened the first time it copies this config over to the
# user's config, so this sets the default effectively.
sed 's/^\(\s*set vicmd=\)vim\(\s*\)$/\1nvim\2/' -i /usr/share/vifm/vifmrc

if [[ "${DEV_TOOLS}" -eq 1 ]]; then
  packages=(
    clang cmake
    shfmt shellcheck
    ccache doxygen graphviz
  )
  pacman -S --noconfirm --needed "${packages[@]}"
  pip install conan cmake-format
fi

if [[ "${CROSS_DEV_TOOLS}" -eq 1 ]]; then
  packages=(
    avr-gcc mingw-w64-gcc
  )
  pacman -S --noconfirm --needed "${packages[@]}"
fi

installed_win32yank=0
if [[ "${RUST_DEV_TOOLS}" -eq 1 ]]; then
  pacman -S --noconfirm --needed rustup
  rustup install stable
  rustup default stable
  if [[ "${CROSS_DEV_TOOLS}" -eq 1 ]]; then
    windows_target='x86_64-pc-windows-gnu'
    rustup target add "${windows_target}"
    if [[ "${WIN32YANK}" -eq 1 ]]; then
      # Build win32yank from source
      tmp_build_dir="$(mktemp -d '/tmp/win32yank.XXXXXXXXXX')"
      tmp_output_dir="${tmp_build_dir}/output"
      git clone 'https://github.com/equalsraf/win32yank.git' "${tmp_build_dir}"
      arguments=(
        build
        --manifest-path="${tmp_build_dir}/Cargo.toml"
        --release
        --target "${windows_target}"
        --target-dir "${tmp_output_dir}"
      )
      cargo "${arguments[@]}"
      cp "${tmp_output_dir}/x86_64-pc-windows-gnu/release/win32yank.exe" /usr/local/bin/
      rm -rf "${tmp_build_dir}"
      installed_win32yank=1
    fi
  fi
fi

if [[ "${WIN32YANK}" -eq 1 && "${installed_win32yank}" -ne 1 ]]; then
  # Use the most recent win32yank release at the time of writing
  tmp_zip="$(mktemp '/tmp/win32yank.XXXXXXXXXX')"
  wget 'https://github.com/equalsraf/win32yank/releases/download/v0.0.4/win32yank-x64.zip' -qO "${tmp_zip}"
  unzip "${tmp_zip}" 'win32yank.exe' -d /usr/local/bin
  rm -f "${tmp_zip}"
fi

# TODO: this will never be true; reworking things
if [[ -n "${WSL_USER}" ]]; then
  echo "- Setting WSL user ${WSL_USER} password to the default."
  echo "${user_name}:${WSL_USER_PASSWORD}" | chpasswd
  if [[ "${WSL_NS_BASHRC}" -eq 1 ]]; then
###############################
    su - "${user_name}" <<'EOF'
set -e
git clone 'https://github.com/nacitar/bashrc.git' "$HOME/.bash"
"$HOME/.bash/install.sh"
EOF
###############################
  fi
  if [[ "${WSL_NS_NEOVIM_CONFIG}" -eq 1 ]]; then
###############################
    su - "${user_name}" <<'EOF'
set -e
config_dir="$HOME/.config/nvim"
rm -rf "$config_dir"
mkdir -p "$config_dir"
git clone "https://github.com/nacitar/neovim-config.git" "$config_dir"
"$config_dir/install_home_bin_forwarder.sh"
EOF
###############################
  fi
fi

# Remove all non-current cached packages
pacman -Sc --noconfirm
