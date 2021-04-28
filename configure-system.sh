#!/bin/bash

error_messages=()

ADD_GROUPS=()
ADD_USERS=()
declare -A ADD_TO_GROUPS
WSL_USER_PASSWORD="archlinux" # default
while (($#)); do
  while [[ "${1}" =~ ^-[^-]{2,}$ ]]; do
    # split out multiflags
    set -- "${1::-1}" "-${1: -1}" "${@:2}"
  done
  case "${1}" in
    -a | --aur-support) AUR_SUPPORT=1 ;;
    -d | --dev-tools) DEV_TOOLS=1 ;;
    -r | --rust-dev-tools) RUST_DEV_TOOLS=1 ;;
    -c | --cross-dev-tools) CROSS_DEV_TOOLS=1 ;;
    -u | --update-pacman) UPDATE_PACMAN=1 ;;
    -g | --generate-pacman-keyring) GENERATE_PACMAN_KEYRING=1 ;;
    -w | --wheel-sudo) WHEEL_SUDO=1 ;;
    --add-groups=*)
      IFS=',' read -r -a individual_groups <<<"${1#*=}"
      ADD_GROUPS+=("${individual_groups[@]}")
      ;;
    --add-users=*)
      IFS=',' read -r -a individual_users <<<"${1#*=}"
      ADD_USERS+=("${individual_users[@]}")
      ;;
    --add-to-groups=*:*)
      raw_value="${1#*=}"
      if [[ "${raw_value}" == *:*:* ]]; then
        error_messages+=("too many colon delimited sections in argument: ${1}")
      else
        IFS=',' read -r -a individual_users <<<"${raw_value%:*}"
        for user_name in "${individual_users[@]}"; do
          ADD_TO_GROUPS["$user_name"]+=",${raw_value#*:}"
        done
      fi
      ;;
    --locale-lang=*) LOCALE_LANG="${1#*=}" ;;
    --force-setting-locale) FORCE_SETTING_LOCALE=1 ;;
    # if specified with RUST_DEV_TOOLS and CROSS_DEV_TOOLS, builds from source
    --win32yank) WIN32YANK=1 ;;
    --wsl-clear-config) WSL_CLEAR_CONFIG=1 ;;
    # forces WHEEL_SUDO
    --wsl-user=*)
      WSL_USER="${1#*=}"
      # due to wsl being configured to start as this user, --wheel-sudo must
      # be forced... otherwise the user has no way of elevating.
      arguments=(
        --wheel-sudo
        --add-groups='wheel'
        --add-users="${WSL_USER}"
        --add-to-groups="${WSL_USER}:wheel"
      )
      set -- "${arguments[@]}" "${@:2}"
      continue
      ;;
    --wsl-user-password=*) WSL_USER_PASSWORD="${1#*=}" ;;
    --wsl-hostname=*) WSL_HOSTNAME="${1#*=}" ;;
    --wsl-docker) WSL_DOCKER=1 ;;
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
    --argument-check) ARGUMENT_CHECK=1 ;;
    -*) error_messages+=("unsupported flag: ${1}") ;;
    *) error_messages+=("unsupported positional argument: ${1}") ;;
  esac
  shift
done
# default the LOCALE if it's being forced but is unspecified.
if [[ -z "${LOCALE_LANG}" && "${FORCE_SETTING_LOCALE}" -eq 1 ]]; then
  LOCALE_LANG='en_US.UTF-8'
fi
# actually apply WSL_DOCKER; couldn't in the switch because WSL_USER could
# have come later in the arguments.
if [[ -n "${WSL_USER}" && "${WSL_DOCKER}" -eq 1 ]]; then
  ADD_GROUPS+=('docker')
  ADD_TO_GROUPS["${WSL_USER}"]+=',docker'
fi

if [[ ${#error_messages[@]} -gt 0 ]]; then
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

if [[ "${UPDATE_PACMAN}" -eq 1 ]]; then
  # update package db (y) and pacman
  pacman -Sy --noconfirm --needed pacman
fi

if [[ "${GENERATE_PACMAN_KEYRING}" -eq 1 ]]; then
  # fixes errors like:
  # - D8AFDDA07A5B6EDFA7D8CCDAD6D055F927843F1C could not be locally signed.
  # https://www.archlinux.org/news/gnupg-21-and-the-pacman-keyring/
  rm -rf /etc/pacman.d/gnupg &>/dev/null
  pacman-key --init
  pacman-key --populate archlinux
fi

if [[ -n "${LOCALE_LANG}" ]]; then
  if ! grep -qE ^"#?${LOCALE_LANG}( |$)" /etc/locale.gen; then
    echo "cannot find specified locale lang in locale.gen: ${LOCALE_LANG}" >&2
    exit 1
  fi
  # uncomment the locale in locale-gen if it's commented
  sed "s/^#\(${LOCALE_LANG}\( \|$\)\)/\1/" -i /etc/locale.gen
  # generate the locale
  locale-gen
  # set the locale
  echo "LANG=${LOCALE_LANG}" >/etc/locale.conf
fi

# Unconditional packages
packages=(
  base-devel
  pacman-contrib
  libcap python python-pip
  reflector
  man man-db man-pages
  keychain openssh
  diffutils colordiff
  zip unzip
  git
  neovim wget
)
pacman -S --noconfirm --needed "${packages[@]}"

# Fix permissions to allow non-root users to ping.  The ping binary comes from
# iputils, and that's a core system package... but it doesn't set this cap.
setcap cap_net_raw+ep /usr/bin/ping

# Install the wheel package so that python packages are packaged better.
# This is unrelated to sudo/the wheel group, just named the same.
python -m pip install wheel

if [[ "${WHEEL_SUDO}" -eq 1 ]]; then
  if grep -q ^"# %wheel ALL=(ALL) ALL"$ /etc/sudoers; then
    # uncomment it if in the expected form
    sed '/^# %wheel ALL=(ALL) ALL$/s/^# //g' -i /etc/sudoers
  elif ! grep -q ^"%wheel ALL=(ALL) ALL"$ /etc/sudoers; then
    # it's not already there, so append it
    (
      echo ''
      echo '## Allow members of group wheel to execute any command'
      echo '%wheel ALL=(ALL) ALL'
    ) >>/etc/sudoers
  fi
  ADD_GROUPS+=("wheel") # just in case
fi

for group_name in "${ADD_GROUPS[@]}"; do
  if ! grep -q ^"${group_name}:" /etc/group; then
    echo "Adding group: ${group_name}"
    groupadd "${group_name}"
  fi
done
for user_name in "${ADD_USERS[@]}"; do
  if ! grep -q ^"${user_name}:" /etc/passwd; then
    echo "Adding user: ${user_name}"
    useradd -m "${user_name}"
  fi
done
for user_name in "${!ADD_TO_GROUPS[@]}"; do
  echo "Setting groups for user: ${user_name}"
  # skipping first character in group list as it is a leading comma
  IFS=',' read -r -a individual_groups <<<"${ADD_TO_GROUPS["${user_name}"]:1}"
  for group_name in "${individual_groups[@]}"; do
    group_line="$(grep ^"${group_name}:" /etc/group)"
    group_members="${group_line##*:}"
    if [[ ! "${group_members}" =~ (,|^)${user_name}(,|$) ]]; then
      echo "- Group: ${group_name}"
      usermod -aG "${group_name}" "${user_name}"
    fi
  done
done

wsl_config=/etc/wsl.conf
if [[ "${WSL_CLEAR_CONFIG}" -eq 1 ]]; then
  if [[ -e "${wsl_config}" ]]; then
    rm -f "${wsl_config}"
  fi
fi
if [[ -n "${WSL_HOSTNAME}" ]]; then
  (
    echo '[network]'
    echo "hostname=${WSL_HOSTNAME}"
    echo
  ) >>"${wsl_config}"
  if [[ -n "${WSL_USER}" ]]; then
    (
      echo '[user]'
      echo "default=${WSL_USER}"
      echo
    ) >>"${wsl_config}"
  fi
fi

if [[ "${AUR_SUPPORT}" -eq 1 ]]; then
  AUR_CACHE_DIRECTORY='/var/cache/pacman/aur'
  AUR_CONFIG_FILE='/etc/pacman.d/aur'
  NOBODY_SUDOERS_FILE='/etc/sudoers.d/nobody_pacman'
  tmp_build_dir="$(mktemp -d '/tmp/aurutils.XXXXXXXXXX')"
  git clone 'https://aur.archlinux.org/aurutils.git' "${tmp_build_dir}"
  pushd "${tmp_build_dir}"
  mkdir "${AUR_CACHE_DIRECTORY}"
  # makepkg cannot be ran as root, so 'nobody' will be used
  # and it needs access to the directory.
  chown -R nobody:nobody .
  echo "nobody ALL=(ALL) NOPASSWD: /usr/bin/pacman" > "${NOBODY_SUDOERS_FILE}"
  remove_nobody_sudoers_file() {
    if [[ -e "${NOBODY_SUDOERS_FILE}" ]]; then
      rm "${NOBODY_SUDOERS_FILE}"
    fi
  }
  cleanup+=(remove_nobody_sudoers_file)
  sudo -u nobody makepkg -s --noconfirm
  remove_nobody_sudoers_file  # early cleanup
  package_file=(aurutils-*.pkg.tar.zst)
  if [[ "${#package_file[@]}" -ne 1 ]]; then
    echo "Expected exactly one package, but found ${#package_file[@]}: ${package_file[@]}" >&2
    exit 1
  fi
  chown root:root "$package_file"
  destination_package_file="${AUR_CACHE_DIRECTORY}/${package_file}"
  mv "${package_file}" "${destination_package_file}"
  popd
  rm -rf "${tmp_build_dir}"
  repo-add "${AUR_CACHE_DIRECTORY}/aur.db.tar.bz2" "$destination_package_file"

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
  if ! grep -q ^"${include_line}"$; then
    # escape the forward slashes in the config path
    sed "s/^\\s*\\[options\\]\\s*$/# enable AUR support\n${include_line//\//\\/}\n[options]/" -i /etc/pacman.conf
  fi
  pacman -Sy
  pacman -S --noconfirm --needed aurutils
fi

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
EOF
###############################
  fi
fi

# This will be a tmpfs, in actuality... clear out the temp files.
rm -rf /run/*
