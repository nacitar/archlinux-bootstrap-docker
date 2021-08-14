# Accepts: base, user
ARG ADMIN_USER=tux
ARG WSL_HOSTNAME

FROM alpine AS bootstrap
ARG MIRROR_URL="https://mirrors.ocf.berkeley.edu/archlinux"
RUN set -euo pipefail \
    && checksum_line="$(set -euo pipefail \
            && wget -qO- "${MIRROR_URL}/iso/latest/sha1sums.txt" \
                | grep '\sarchlinux-bootstrap-\S\+-x86_64\.tar\.gz$' \
        )" \
    && tarball="${checksum_line##* }" \
    && wget "${MIRROR_URL}/iso/latest/${tarball}" \
    && echo "${checksum_line}" | sha1sum -c \
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
    && rm -rf /etc/pacman.d/gnupg &>/dev/null \
    && pacman-key --init \
    && pacman-key --populate archlinux \
    && pacman -Syu --noconfirm --needed base \
    && mkdir -p /run/shm \
    && sed "s/^#\(${LOCALE_LANG}\( \|$\)\)/\1/" -i /etc/locale.gen \
    && locale-gen \
    && echo "LANG=${LOCALE_LANG}" > /etc/locale.conf \
    && pacman -Sc --noconfirm
CMD ["/bin/bash"]

FROM base AS user
ARG ADMIN_USER
ARG DEFAULT_PASSWORD=archlinux
ARG WSL_HOSTNAME
ARG NO_DOCKER_GROUP
RUN set -euo pipefail \
    && pacman -S --noconfirm --needed python python-pip \
    && python -m pip install wheel \
    && pacman -S --noconfirm --needed reflector pacman-contrib sudo \
    && setcap cap_net_raw+ep /usr/bin/ping \
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
    ; fi \
    && pacman -Sc --noconfirm

FROM user AS aurutils
ARG ADMIN_USER
ARG AURUTILS_GIT="https://aur.archlinux.org/aurutils.git"
ARG VIFM_VICMD="nvim"
RUN set -euo pipefail \
    && pacman -S --noconfirm --needed git base-devel \
    && cache_directory=/var/cache/pacman/aur \
    && build_directory=/tmp/aurutils \
    && install -d -m 775 -o "${ADMIN_USER}" -g "${ADMIN_USER}" \
        "${cache_directory}" \
    && makepkg_sudoers='/etc/sudoers.d/wheel_pacman_nopasswd' \
    && echo "%wheel ALL=(ALL) NOPASSWD: /usr/sbin/pacman" \
        > "${makepkg_sudoers}" \
    && su "${ADMIN_USER}" -c "$(set -euo pipefail \
            && printf "%s\n" \
                'set -euo pipefail' \
                "git clone '${AURUTILS_GIT}' '${build_directory}'" \
                "cd '${build_directory}'" \
                'makepkg -s --noconfirm' \
                "mv *.pkg.tar.zst '${cache_directory}/'" \
                "cd '${cache_directory}'" \
                "rm -rf '${build_directory}'" \
                "repo-add '${cache_directory}/aur.db.tar.bz2' *.pkg.tar.zst" \
        )" \
    && rm "${makepkg_sudoers}" \
    && aur_config=/etc/pacman.d/aur \
    && printf '%s\n' \
        '[options]' \
        '# use original CacheDir but allow falling back to the AUR CacheDir' \
        'CacheDir = /var/cache/pacman/pkg' \
        "CacheDir = ${cache_directory}" \
        'CleanMethod = KeepCurrent' \
        '' \
        '[aur]' \
        'SigLevel = Optional TrustAll' \
        "Server = file://${cache_directory}" \
        > "${aur_config}" \
    && content="$(set -euo pipefail \
            && printf '%s\\n' \
                '# AUR support: aurutils uses first file:// Server entry' \
                "Include = ${aur_config}" \
        )" \
    && sed 's/^\s*\(\[options\]\)\s*$/\n'"${content//\//\\/}"'\n\1/' \
        -i /etc/pacman.conf \
    && pacman -Sy --noconfirm \
    && pacman -S --noconfirm --needed aurutils vifm \
    && case "${VIFM_VICMD}" in \
        vim) pacman -S --noconfirm --needed vim ;; \
        nvim) pacman -S --noconfirm --needed neovim ;; \
        *) echo "Unsupported vicmd: ${VIFM_VICMD}" >&2 \
            && exit 1 ;; \
    esac \
    && if [ "${VIFM_VICMD}" != 'vim' ]; then \
        sed 's/^\(\s*set vicmd=\)vim\(\s*\)$/\1'"${VIFM_VICMD}"'\2/' \
            -i /usr/share/vifm/vifmrc \
    ; fi \
    && pacman -Sc --noconfirm

FROM aurutils AS nacitar
ARG WSL_HOSTNAME
ARG NO_DEV_TOOLS
ARG NO_CROSS_DEV_TOOLS
ARG NO_BASHRC
ARG NO_NEOVIM_CONFIG
ARG WIN32YANK_VERSION="v0.0.4"
RUN set -euo pipefail \
    && python -m pip install virtualenv pipenv \
    && pacman -S --noconfirm --needed \
        keychain openssh wget lsof \
        diffutils colordiff \
        zip unzip \
        neovim \
    && if [ -z "${NO_DEV_TOOLS:-}" ]; then \
        pacman -S --noconfirm --needed \
            clang cmake \
            shfmt shellcheck \
            ccache doxygen graphviz \
        && python -m pip install conan cmake-format \
    ; fi \
    && if [ -z "${NO_CROSS_DEV_TOOLS:-}" ]; then \
        pacman -S --noconfirm --needed avr-gcc mingw-w64-gcc \
    ; fi \
    && if [ -n "${WSL_HOSTNAME:-}" ] && [ -n "${WIN32YANK_VERSION:-}" ]; then \
        base_url=https://github.com/equalsraf/win32yank/releases/download \
        && release_url="${base_url}/${WIN32YANK_VERSION}/win32yank-x64.zip" \
        && wget "${release_url}" -qO release.zip \
        && unzip release.zip win32yank.exe -d /usr/local/bin \
        && rm release.zip \
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

FROM aurutils AS final
