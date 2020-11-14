#!/bin/bash
set -e

get_script_directory() {
	SOURCE="${BASH_SOURCE[0]}"
	while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
		DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
		SOURCE="$(readlink "$SOURCE")"
		[[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
	done
	DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
	echo "$DIR"
}

script_directory="$(get_script_directory)"

source "$script_directory/common.sh"

require_root_privilege


# FROM ENVIRONMENT
# - ADMIN_USER
# - TOOLS


# fixes errors like: D8AFDDA07A5B6EDFA7D8CCDAD6D055F927843F1C could not be locally signed.
# https://www.archlinux.org/news/gnupg-21-and-the-pacman-keyring/
rm -rf /etc/pacman.d/gnupg &>/dev/null
pacman-key --init
result_message_or_fail 2 "initialize new pacman keyring"
pacman-key --populate archlinux
result_message_or_fail 3 "populate new pacman keyring"

if [[ -n "$ADMIN_USER" ]]; then
	useradd -m "$ADMIN_USER"
	result_message_or_fail 4 "create user $ADMIN_USER"
	usermod -aG wheel "$ADMIN_USER"
	result_message_or_fail 5 "add user $ADMIN_USER to wheel"
	(
		echo '[user]'
		echo "default=$ADMIN_USER"
	) > /etc/wsl.conf
	result_message_or_fail 6 "set wsl default user to $ADMIN_USER"
fi

echo 'LANG=en_US.UTF-8' > /etc/locale.conf
result_message_or_fail 7 "set system locale"

locale-gen
result_message_or_fail 8 "generate locales"

pacman -Syu --noconfirm sudo
result_message_or_fail 9 "install sudo"

# if it has the string we expect/have seen in the past
if cat /etc/sudoers | grep "# %wheel ALL=(ALL) ALL" &>/dev/null; then
	# uncomment it
	sed '/^# %wheel ALL=(ALL) ALL$/s/^# //g' -i /etc/sudoers
	result_message_or_fail 10 "uncomment wheel sudo access"
else
	(
		echo
		echo '## Allow members of group wheel to execute any command'
		echo '%wheel ALL=(ALL) ALL'
	) >> /etc/sudoers
	result_message_or_fail 11 "add wheel sudo access"
fi

