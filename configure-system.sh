#!/bin/bash

error_messages=()

ADD_GROUPS=()
ADD_USERS=()
declare -A ADD_TO_GROUPS
WSL_DEFAULT_USER_PASSWORD="archlinux" # default
while (($#)); do
  while [[ $1 =~ ^-[^-]{2,}$ ]]; do
    set -- "${1::-1}" "-${1: -1}" "${@:2}" # split out multiflags
  done
  case "$1" in
    -e | --essential-tools) ESSENTIAL_TOOLS=1 ;;
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
      if [[ $raw_value == *:*:* ]]; then
        error_messages+=("too many colon delimited sections in argument: $1")
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
    --wsl-default-user=*) WSL_DEFAULT_USER="${1#*=}" ;;
    --wsl-default-user-password=*) WSL_DEFAULT_USER_PASSWORD="${1#*=}" ;;
    --wsl-hostname=*) WSL_HOSTNAME="${1#*=}" ;;
    --argument-check) ARGUMENT_CHECK=1 ;;
    -*) error_messages+=("unsupported flag: $1") ;;
    *) error_messages+=("unsupported positional argument: $1") ;;
  esac
  shift
done
if [[ -z $LOCALE_LANG && $FORCE_SETTING_LOCALE -eq 1 ]]; then
  LOCALE_LANG="en_US.UTF-8" # default if forcing
fi
if [[ -n $WSL_DEFAULT_USER ]]; then
  ADD_USERS+=("$WSL_DEFAULT_USER")
  ADD_TO_GROUPS["$WSL_DEFAULT_USER"]+=',wheel'
  WHEEL_SUDO=1 # force this parameter on; WSL is useless otherwise
fi
if [[ ${#error_messages[@]} -gt 0 ]]; then
  printf "%s\n" "${error_messages[@]}" >&2
  exit 1
fi
if [[ $ARGUMENT_CHECK -eq 1 ]]; then
  exit 0
fi

if [[ $EUID -ne 0 ]]; then
  echo 'script must be run as root' >&2
fi

set -e # exit upon error

if [[ $UPDATE_PACMAN -eq 1 ]]; then
  # update package db (y) and pacman
  pacman -Sy --noconfirm --needed pacman
fi

if [[ $GENERATE_PACMAN_KEYRING -eq 1 ]]; then
  # fixes errors like: D8AFDDA07A5B6EDFA7D8CCDAD6D055F927843F1C could not be locally signed.
  # https://www.archlinux.org/news/gnupg-21-and-the-pacman-keyring/
  rm -rf /etc/pacman.d/gnupg &>/dev/null
  pacman-key --init
  pacman-key --populate archlinux
fi

if [[ -n $LOCALE_LANG ]]; then
  echo "LANG=$LOCALE_LANG" >/etc/locale.conf
  locale-gen
fi

if [[ $WHEEL_SUDO -eq 1 ]]; then
  pacman -S --noconfirm --needed sudo sed
  if grep -q ^"# %wheel ALL=(ALL) ALL"$ /etc/sudoers; then
    # uncomment it if in the expected form
    sed '/^# %wheel ALL=(ALL) ALL$/s/^# //g' -i /etc/sudoers
  elif ! grep -q ^"%wheel ALL=(ALL) ALL"$ /etc/sudoers; then
    # it's not already there, so append it
    (
      echo
      echo '## Allow members of group wheel to execute any command'
      echo '%wheel ALL=(ALL) ALL'
    ) >>/etc/sudoers
  fi
  ADD_GROUPS+=("wheel") # just in case
fi

for group_name in "${ADD_GROUPS[@]}"; do
  if ! grep -q ^"$group_name:" /etc/group; then
    echo "Adding group: $group_name"
    groupadd "$group_name"
  fi
done
for user_name in "${ADD_USERS[@]}"; do
  if ! grep -q ^"$user_name:" /etc/passwd; then
    echo "Adding user: $user_name"
    useradd -m "$user_name"
    if [[ "${user_name}" == "${WSL_DEFAULT_USER}" ]]; then
      echo "- WSL default user, setting password to the default."
      pacman -S --noconfirm --needed shadow # for chpasswd
      echo "$user_name:$WSL_DEFAULT_USER_PASSWORD" | chpasswd
    fi

  fi
done
for user_name in "${!ADD_TO_GROUPS[@]}"; do
  echo "Setting groups for user: $user_name"
  # skipping first character in group list as it is a leading comma
  IFS=',' read -r -a individual_groups <<<"${ADD_TO_GROUPS[$user_name]:1}"
  for group_name in "${individual_groups[@]}"; do
    group_line="$(grep ^"$group_name:" /etc/group)"
    group_members="${group_line##*:}"
    if [[ ! $group_members =~ (,|^)$user_name(,|$) ]]; then
      echo "- Group: $group_name"
      usermod -aG "$group_name" "$user_name"
    fi
  done
done

wsl_config='/etc/wsl.conf'
if [[ $WSL_CLEAR_CONFIG -eq 1 ]]; then
  if [[ -e $wsl_config ]]; then
    rm -f "$wsl_config"
  fi
fi
if [[ -n $WSL_DEFAULT_USER ]]; then
  (
    echo '[user]'
    echo "default=$WSL_DEFAULT_USER"
    echo
  ) >>"$wsl_config"
fi
if [[ -n $WSL_HOSTNAME ]]; then
  (
    echo '[network]'
    echo "hostname=$WSL_HOSTNAME"
    echo
  ) >>"$wsl_config"
fi

if [[ $ESSENTIAL_TOOLS -eq 1 ]]; then
  packages=(
    reflector
    procps-ng file which
    sed gawk diffutils colordiff
    git neovim wget
    man man-db man-pages
    tar gzip zip unzip
  )
  pacman -S --noconfirm --needed "${packages[@]}"
fi

if [[ $DEV_TOOLS -eq 1 ]]; then
  packages=(
    gcc clang make cmake python-pip
    m4 automake
  )
  pacman -S --noconfirm --needed "${packages[@]}"
  pip install conan
fi

if [[ $CROSS_DEV_TOOLS -eq 1 ]]; then
  packages=(
    avr-gcc mingw-w64-gcc
  )
  pacman -S --noconfirm --needed "${packages[@]}"
fi

installed_win32yank=0
if [[ $RUST_DEV_TOOLS -eq 1 ]]; then
  pacman -S --noconfirm --needed rustup
  rustup install stable
  rustup default stable
  if [[ $CROSS_DEV_TOOLS -eq 1 ]]; then
    windows_target=x86_64-pc-windows-gnu
    rustup target add $windows_target
    if [[ $WIN32YANK -eq 1 ]]; then
      # Build win32yank from source
      tmp_build_dir="$(mktemp -d /tmp/win32yank.XXXXXXXXXX)"
      tmp_output_dir="$tmp_build_dir/output"
      pacman -S --noconfirm --needed git
      git clone 'https://github.com/equalsraf/win32yank.git' "$tmp_build_dir"
      cargo build --manifest-path="$tmp_build_dir/Cargo.toml" --release --target $windows_target --target-dir "$tmp_output_dir"
      cp "$tmp_output_dir/x86_64-pc-windows-gnu/release/win32yank.exe" /usr/local/bin/
      rm -rf "$tmp_build_dir"
      installed_win32yank=1
    fi
  fi
fi

if [[ $WIN32YANK -eq 1 && $installed_win32yank -ne 1 ]]; then
  # Use the most recent win32yank release at the time of writing
  pacman -S --noconfirm --needed wget unzip
  tmp_zip="$(mktemp /tmp/win32yank.XXXXXXXXXX)"
  wget 'https://github.com/equalsraf/win32yank/releases/download/v0.0.4/win32yank-x64.zip' -qO "$tmp_zip"
  unzip "$tmp_zip" win32yank.exe -d /usr/local/bin
  rm -f "$tmp_zip"
fi

# This will be a tmpfs, in actuality... clear out the temp files.
rm -rf /run/*
