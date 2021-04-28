# wsl-archlinux
Scripts to generate an archlinux wsl importable tar file from an ubuntu wsl2 terminal with docker.

# Example Usage
```
sudo ./build-tar.sh -adrc --win32yank --wsl-user='tux' --wsl-hostname='archlinux' --wsl-ns-all
```
If you aren't a rust developer, remove -r from the flags.  If you don't want cross compilation tools,
remove -c from the flags.  These will shrink the image greatly.

If you want the final docker container to be kept, add --keep-image

If developing the configuration script, adding --reuse-base-image will prevent pointless re-pacstrapping
