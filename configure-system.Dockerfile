FROM wsl-archlinux:base
ARG ALL_ARGUMENTS
COPY configure-system.sh /
RUN bash /configure-system.sh ${ALL_ARGUMENTS}
RUN rm /configure-system.sh
CMD /usr/bin/bash
