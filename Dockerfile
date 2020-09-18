FROM archlinux:latest
COPY [ "bootstrap.sh", "/" ]
COPY [ "common.sh", "/" ]
ENTRYPOINT [ "bash", "/bootstrap.sh" ]
