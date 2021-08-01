FROM archlinux:latest AS tarball-pacstrapper
RUN pacman -Sy --noconfirm --needed pacman \
    && pacman -S --noconfirm --needed reflector \
    && reflector -l 20 -p https --sort rate --save /etc/pacman.d/mirrorlist \
    && pacman -Su --noconfirm \
    && pacman -S --noconfirm --needed arch-install-scripts

COPY ./app/ /app/
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
#CMD ["base"]

