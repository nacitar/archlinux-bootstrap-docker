# Accepts: base, configured
ARG TARGET=configured

FROM alpine AS bootstrap
ARG MIRROR_URL="https://mirrors.ocf.berkeley.edu/archlinux"
RUN set -eo pipefail \
    && checksum_line="$(wget -qO- "${MIRROR_URL}/iso/latest/sha1sums.txt" \
        | grep '\sarchlinux-bootstrap-\S\+-x86_64\.tar\.gz$')" \
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

FROM scratch AS archlinux-base
ARG LOCALE_LANG="en_US.UTF-8"
COPY --from=bootstrap /rootfs/ /
RUN set -eo pipefail \
    && rm -rf /etc/pacman.d/gnupg &>/dev/null \
    && pacman-key --init \
    && pacman-key --populate archlinux \
    && pacman -Syu --noconfirm --needed base \
    && sed "s/^#\(${LOCALE_LANG}\( \|$\)\)/\1/" -i /etc/locale.gen \
    && locale-gen \
    && echo "LANG=${LOCALE_LANG}" > /etc/locale.conf \
    && pacman -Sc --noconfirm 
CMD ["/bin/bash"]

FROM archlinux-base AS archlinux-configured
ARG DEFAULT_USER=tux
ARG DEFAULT_PASSWORD=archlinux
ARG WSL_HOSTNAME
ARG NO_DOCKER_GROUP
RUN set -eo pipefail \
    && pacman -S --noconfirm --needed python python-pip \
    && python -m pip install wheel \
    && pacman -S --noconfirm --needed reflector pacman-contrib \
    && mkdir -p /run/shm \
    && setcap cap_net_raw+ep /usr/bin/ping \
    ; if [ -n "${DEFAULT_USER}" ]; then \
        pacman -S --noconfirm --needed sudo \
        && echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel \
        && useradd -G wheel -m "${DEFAULT_USER}" \
        && printf '%s:%s' "${DEFAULT_USER}" "${DEFAULT_PASSWORD}" | chpasswd \
        ; if [ -z "${NO_DOCKER_GROUP}" ]; then \
            groupadd docker \
            && usermod -aG docker "${DEFAULT_USER}" \
        ; fi \
    ; fi \
    ; if [ -n "${WSL_HOSTNAME}" ]; then \
        ( \
            printf '%s\n' '[network]' "hostname=${WSL_HOSTNAME}" \
            ; if [ -n "${DEFAULT_USER}" ]; then \
                printf '\n%s\n' '[user]' "default=${DEFAULT_USER}" \
            ; fi \
        ) > /etc/wsl.conf \
    ; fi \
    && pacman -Sc --noconfirm 

FROM archlinux-${TARGET} as final
