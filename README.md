# archlinux-bootstrap-docker
A Dockerfile that prepares an ArchLinux system from the bootstrap tarball
provided by an ArchLinux mirror.  The Dockerfile is has several stages that
can be directly targetted to control how much has been done to the resultant
image.  Listed from least work to most work:
- base: The bootstrap image with an initialized pacman keyring and the
selected locale prepared.
- user: The base configuration expanded to include extra pacman utilities,
reflector to generate mirrorlists, and a sudo-enabled non-root admin user.
- aurutils: The user configuration expanded to include aurutils configured to
work with the admin user.
- nacitar: The aurutils configuration expanded to include extra utilities that
the author of this repository finds useful and sets the admin user to use a
particular bashrc and neovim config.

The default target is aurutils.

# Build Arguments
There are several build arguments that can be provided to customize the output
image, but none are required and defaults are provided in the Dockerfile.

- MIRROR\_URL: The base url of the pacman mirror to use.
(Default: https://mirrors.rit.edu/archlinux)
- ADMIN\_USER: A sudo-enabled non-root admin user to create. (Default: tux)
- DEFAULT\_PASSWORD: The password for the admin user. (Default: archlinux)
- LOCALE\_LANG: The locale to select (Default: en\_US.UTF-8)
- WSL\_HOSTNAME: The hostname to use in WSL.  Specifying any non-empty
value for this argument will also lead to the admin user becoming the default
user for WSL.  This configuration lives in /etc/wsl.conf.
- NO\_DOCKER\_GROUP: If specified, the admin user will not be added to the
docker group.
- VIFM\_VICMD: Which vicmd to use in the system's default vifmrc, because
aurutils uses vifm and it does not use neovim by default.  Can be set to
either vim or nvim. (Default: nvim)

There are other options for the nacitar stage, but they will not be documented
here.

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
