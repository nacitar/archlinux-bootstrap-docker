# wsl-archlinux
A docker image that prepares an archlinux system.

# Example Usage
```
docker build .
docker export <id>
wsl import
wsl rm /.dockerenv
```
# WIP
Suggest using reflector:
```
reflector --country US --protocol https --age 24 --fastest 10 --sort rate --save /etc/pacman.d/mirrorlist
```
