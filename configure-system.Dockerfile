FROM wsl-archlinux:base
ARG ADMIN_USER
ARG TOOLS
COPY configure-system.sh /
COPY common.sh /
RUN /configure-system.sh
RUN rm /configure-system.sh /common.sh
ENTRYPOINT [ "bash" ]
