FROM wsl-archlinux:base
ARG ADMIN_USER
ARG ESSENTIAL_TOOLS
ARG DEV_TOOLS
ARG CROSS_DEV_TOOLS
COPY configure-system.sh /
RUN env
RUN /configure-system.sh
RUN rm /configure-system.sh
ENTRYPOINT bash
