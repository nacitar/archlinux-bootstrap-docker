#!/bin/bash

success_message() {  # <message...>
	echo "SUCCESS: $@" >&2
}

fail_message() {  # <message...>
	echo "FAILURE: $@" >&2
}

fail() {  # <exit_code> <message...>
	fail_message "${@:2}"
	exit "$1"
}

result_message() {  # <message>
	if (( $? == 0 )); then
		success_message "$@"
	else
		fail_message "$@"
	fi
	return $?
}

result_message_or_fail() {  # <exit_code> <message...>
	if ! result_message "${@:2}"; then
		exit "$1"
	fi	
}
require_root_privilege() {
	if (( $EUID != 0 )); then
		fail 1 "script must be run as root"
	fi
}
