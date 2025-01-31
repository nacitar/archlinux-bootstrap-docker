#!/bin/bash

# NOTE: will print to the terminal weirdly due to needing to escape \ with \\\\
# but it will work perfectly when written to /etc/issue
echo -e '\e[H\e[2J\e[0;36m'
echo -e '          ##'
echo -e '         ####                       _     _ _'
echo -e '        ######        __ _ _ __ ___| |__ | (_)_ __  _   ___  __'
echo -e '       ########      / _` | '\''__/ __| '\''_ \\\\| | | '\''_ \\\\| | | \\\\ \\\\/ /'
echo -e '      ##########    | (_| | | | (__| | | | | | | | | |_| |>  <'
echo -e '     #####  #####    \\\\__,_|_|  \\\\___|_| |_|_|_|_| |_|\\\\__,_/_/\\\\_\\\\'
echo -e '    ####      ####'
echo -e '   #####      #####   \e[1;37mA simple, elegant gnu/linux distribution.\e[0;36m'
echo -e '  ##              ##'
echo -e '\e[0m'
echo '\S{PRETTY_NAME} \r (\l)'
echo ''
