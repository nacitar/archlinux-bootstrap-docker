#!/usr/bin/env bash
> files/archlinux-image.tar.gz
docker build --rm -t pacstrap:latest -f tarball-pacstrapper.Dockerfile .
docker run --privileged --mount type=bind,src="${PWD}/files",dst=/files -it pacstrap:latest # -yd --wsl-user='tux' --wsl-hostname='archlinux' --wsl-ns-all
