#!/bin/bash

# NOTE: will print to the terminal weirdly due to needing to escape \ with \\\\
# but it will work perfectly when written to /etc/issue
echo -e '\e[H\e[2J\e[0;36m'
echo -e '          ##'
echo -e '         ####\e[1m                       _     _ _\e[22m'
echo -e '        ######\e[1m        __ _ _ __ ___| |__ | (_)_ __  _   ___  __\e[22m'
echo -e '       ########\e[1m      / _` | '\''__/ __| '\''_ \\\\| | | '\''_ \\\\| | | \\\\ \\\\/ /\e[22m'
echo -e '      ##########\e[1m    | (_| | | | (__| | | | | | | | | |_| |>  <\e[22m'
echo -e '     #####  #####\e[1m    \\\\__,_|_|  \\\\___|_| |_|_|_|_| |_|\\\\__,_/_/\\\\_\\\\\e[22m'
echo -e '    ####      ####'
echo -e '   #####      #####   \e[1;37mA simple, elegant gnu/linux distribution.\e[0;36m'
echo -e '  ##              ##'
echo -e '\e[0m'
echo '\S{PRETTY_NAME} \r (\l)'
echo ''
