# wsl-archlinux
Scripts to generate an archlinux wsl importable tar file from an ubuntu wsl2 terminal with docker.

# Example Usage
```
sudo ./build-tar.sh -edrc --win32yank --wsl-user='tux' --wsl-hostname='archlinux' --wsl-ns-all
```
If you want the final docker container to be kept, add --keep-image

If developing the configuration script, adding --reuse-base-image will prevent pointless re-pacstrapping
