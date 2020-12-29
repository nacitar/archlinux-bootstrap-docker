# wsl-archlinux
Scripts to generate an archlinux wsl importable tar file from an ubuntu wsl2 terminal with docker.

# Example Usage
```
wsl_user=tux; sudo ./build-tar.sh --essential-tools --dev-tools --rust-dev-tools --cross-dev-tools --win32yank --wheel-sudo --add-groups=wheel,docker --add-users="$wsl_user" --add-to-groups="$wsl_user":wheel,docker --wsl-default-user="$wsl_user" --wsl-hostname=archlinux
```
If you want the final docker container to be kept, add --keep-image

If developing the configuration script, adding --reuse-base-image will prevent pointless re-pacstrapping
