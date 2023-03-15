ARG ADMIN_USER=tux

FROM alpine AS bootstrap
ARG MIRROR_URL="https://mnvoip.mm.fcix.net/archlinux"
RUN set -euo pipefail \
    && checksum_line="$(set -euo pipefail \
            && wget -qO- "${MIRROR_URL}/iso/latest/sha256sums.txt" \
                | grep '\sarchlinux-bootstrap-\S\+-x86_64\.tar\.gz$' \
        )" \
    && tarball="${checksum_line##* }" \
    && wget "${MIRROR_URL}/iso/latest/${tarball}" \
    && echo "${checksum_line}" | sha256sum -c \
    && mkdir /rootfs \
    && tar \
        --extract -z -f "${tarball}" \
        --strip-components=1 --numeric-owner \
        -C /rootfs \
    && rm -f "${tarball}" /rootfs/README \
    && echo "Server = ${MIRROR_URL}/\$repo/os/\$arch" \
        > /rootfs/etc/pacman.d/mirrorlist

FROM scratch AS base
ARG LOCALE_LANG="en_US.UTF-8"
COPY --from=bootstrap /rootfs/ /
RUN set -euo pipefail \
    && pacman-key --init \
    && pacman-key --populate archlinux \
    && pacman -Syu --noconfirm --needed base \
    && sed "s/^#\(${LOCALE_LANG}\( \|$\)\)/\1/" -i /etc/locale.gen \
    && locale-gen \
    && echo "LANG=${LOCALE_LANG}" > /etc/locale.conf \
    && setcap cap_net_raw+ep /usr/bin/ping \
    && pacman -Sc --noconfirm
CMD ["/bin/bash"]

FROM base AS user
ARG ADMIN_USER
ARG DEFAULT_PASSWORD=archlinux
ARG WSL_HOSTNAME
ARG NO_DOCKER_GROUP
ARG WIN32YANK_VERSION="0.0.4"
RUN set -euo pipefail \
    && pacman -S --noconfirm --needed python python-wheel \
    && pacman -S --noconfirm --needed \
        python-pip python-virtualenv python-pipenv \
        reflector pacman-contrib sudo \
    && echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel \
    && useradd -G wheel -m "${ADMIN_USER}" \
    && printf '%s:%s' "${ADMIN_USER}" "${DEFAULT_PASSWORD}" | chpasswd \
    && if [ -z "${NO_DOCKER_GROUP:-}" ]; then \
        groupadd docker \
        && usermod -aG docker "${ADMIN_USER}" \
    ; fi \
    && if [ -n "${WSL_HOSTNAME:-}" ]; then \
        printf '%s\n' \
            '[network]' "hostname=${WSL_HOSTNAME}" \
            '' \
            '[user]' "default=${ADMIN_USER}" \
            > /etc/wsl.conf \
        && if [ -n "${WIN32YANK_VERSION:-}" ]; then \
            base_url=https://github.com/equalsraf/win32yank/releases/download \
            && version_base_url="${base_url}/v${WIN32YANK_VERSION}" \
            && curl -L "${version_base_url}/win32yank-x64.zip" -o - \
                | bsdtar -x -f - -C /usr/local/bin win32yank.exe \
        ; fi \
    ; fi \
    && pacman -Sc --noconfirm

FROM user AS yay
ARG ADMIN_USER
RUN set -euo pipefail \
    && pacman -S --noconfirm --needed git base-devel vifm neovim \
    && sed 's/^\(\s*set vicmd=\)vim\(\s*\)$/\1nvim\2/' \
            -i /usr/share/vifm/vifmrc \
    && yay_git=https://aur.archlinux.org/yay.git \
    && build_directory=/tmp/yay \
    && makepkg_temporary_sudoers='/etc/sudoers.d/wheel_pacman_nopasswd' \
    && echo "%wheel ALL=(ALL) NOPASSWD: /usr/sbin/pacman" \
        > "${makepkg_temporary_sudoers}" \
    && su "${ADMIN_USER}" -c "$(set -euo pipefail \
            && printf "%s\n" \
                'set -euo pipefail' \
                "git clone '${yay_git}' '${build_directory}'" \
                "cd '${build_directory}'" \
                'makepkg -si --noconfirm' \
                'cd -' \
                "rm -rf '${build_directory}'" \
        )" \
    && rm "${makepkg_temporary_sudoers}" \
    && pacman -Sc --noconfirm

FROM yay AS nacitar
ARG NO_DEV_TOOLS
ARG NO_CROSS_DEV_TOOLS
ARG NO_BASHRC
ARG NO_NEOVIM_CONFIG
RUN set -euo pipefail \
    && pacman -S --noconfirm --needed \
        keychain openssh lsof \
        diffutils colordiff \
        zip unzip \
    && if [ -z "${NO_DEV_TOOLS:-}" ]; then \
        pacman -S --noconfirm --needed \
            clang cmake \
            shfmt shellcheck \
            ccache doxygen graphviz \
        && su "${ADMIN_USER}" -c "$(set -euo pipefail \
                && python -m pip install conan cmake-format \
            )" \
    ; fi \
    && if [ -z "${NO_CROSS_DEV_TOOLS:-}" ]; then \
        pacman -S --noconfirm --needed avr-gcc mingw-w64-gcc \
    ; fi \
    && if [ -z "${NO_BASHRC:-}" ]; then \
        bashrc_git=https://github.com/nacitar/bashrc.git \
        && su "${ADMIN_USER}" -c "$(set -euo pipefail \
                && printf "%s\n" \
                    'set -euo pipefail' \
                    'git clone '"${bashrc_git}"' "${HOME}/.bash"' \
                    '${HOME}/.bash/install.sh' \
            )" \
    ; fi \
    && if [ -z "${NO_NEOVIM_CONFIG:-}" ]; then \
        neovim_config_git=https://github.com/nacitar/neovim-config.git \
        && su "${ADMIN_USER}" -c "$(set -euo pipefail \
                && printf "%s\n" \
                    'set -euo pipefail' \
                    'config_dir="${HOME}/.config/nvim"' \
                    'git clone '"${neovim_config_git}"' "${config_dir}"' \
                    '"${config_dir}/install_home_bin_forwarder.sh"' \
            )" \
    ; fi \
    && pacman -Sc --noconfirm

FROM yay AS final
#USER ${ADMIN_USER}
#WORKDIR /home/${ADMIN_USER}
