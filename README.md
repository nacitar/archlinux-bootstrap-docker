# wsl-archlinux
Scripts to generate an archlinux wsl importable tar file from an ubuntu wsl2 terminal with docker.

# Example Usage
```
./build-tarball.sh -yd --wsl-user='tux' --wsl-hostname='archlinux' --wsl-ns-all
```
If you are a rust developer, add -r or --rust-dev-tools
If you want cross compilation tools, add -c or --cross-dev-tools
If you want the final docker container to be kept, add --keep-image
If developing the configuration script, adding --reuse-base-image will prevent pointless re-pacstrapping
