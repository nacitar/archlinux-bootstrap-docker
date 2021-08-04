FROM archlinux:latest AS wsl-archlinux-tarball-creator
RUN pacman -Sy --noconfirm --needed pacman \
    && pacman -S --noconfirm --needed reflector \
    && reflector -l 20 -p https --sort rate --save /etc/pacman.d/mirrorlist \
    && pacman -Su --noconfirm \
    && pacman -S --noconfirm --needed arch-install-scripts zip

COPY ./app/ /app/
RUN chmod +x /app/*.sh  # windows host support?

ENTRYPOINT ["/app/entrypoint.sh"]
#CMD ["base"]

