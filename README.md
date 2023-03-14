# archlinux-bootstrap-docker
A Dockerfile that prepares an ArchLinux system from the bootstrap tarball
provided by an ArchLinux mirror.  The Dockerfile has several stages that can be
directly targeted to control how much has been done to the resultant image.
Listed from least work to most work:
- base: The bootstrap image with an initialized pacman keyring and the
selected locale prepared.
- user: The base configuration expanded to include extra pacman utilities,
reflector to generate mirrorlists, and a sudo-enabled non-root admin user.  If
WSL\_HOSTNAME is specified /etc/wsl.conf will also be configured and win32yank
will be installed.
- yay: The user configuration expanded to include yay configured to
work with the admin user.  Because makepkg uses vifm this also configures vifm
to use neovim and installs neovim.
- nacitar: The yay configuration expanded to include extra utilities that
the author of this repository finds useful and sets the admin user to use a
particular bashrc and neovim config.

The default target is yay.

# Build Arguments
There are several build arguments that can be provided to customize the output
image, but none are required and defaults are provided in the Dockerfile.

- MIRROR\_URL: The base url of the pacman mirror to use.
(Default: https://mnvoip.mm.fcix.net/archlinux)
- ADMIN\_USER: A sudo-enabled non-root admin user to create. (Default: tux)
- DEFAULT\_PASSWORD: The default password for the admin user. (Default:
archlinux)
- LOCALE\_LANG: The locale to select (Default: en\_US.UTF-8)
- WSL\_HOSTNAME: If specified, /etc/wsl.conf will be created with the provided 
hostname entry and the default user will also be set to the ADMIN\_USER.
- WIN32YANK\_VERSION: When WSL\_HOSTNAME is specified the win32yank binary is
installed in order to allow neovim's unnamedplus clipboard mode to access the
windows system clipboard from within WSL.  If an empty string is specified this
will be skipped. (Default: 0.0.4)
- NO\_DOCKER\_GROUP: If specified, the admin user will not be added to the
docker group.

There are other arguments for the nacitar stage, but they will not be
documented.

# Example Usage
The simplest use case is obtaining a docker image of an ArchLinux base system:
```
docker build -t archlinux-base --target base .
```

One of the most involved use cases is creating an ArchLinux distro within WSL.
Assuming you created C:\WSL and want your distro to be in C:\WSL\ArchLinux:
```
docker build -t wsl-archlinux \
    --build-arg WSL_HOSTNAME=archlinux --build-arg ADMIN_USER=tux \
    .
docker create --name wsl-archlinux wsl-archlinux
docker export wsl-archlinux -o wsl-archlinux.tar
docker rm wsl-archlinux
docker rmi wsl-archlinux
wsl import ArchLinux C:\WSL\ArchLinux wsl-archlinux.tar
```
Then simply delete wsl-archlinux.tar.  Note that because docker unavoidably
forces a /.dockerenv file within the tar when you export it, combined with the
fact that it forces it to be owned by root, you must elevate in order to remove
it.  You will be prompted for your user's password, which by default will be
"archlinux":
```
wsl -d ArchLinux sudo rm /.dockerenv
```
Change the password to something secure:
```
wsl -d ArchLinux passwd
```
And then your WSL system should be imported and ready to use.

# Recommendations
Immediately change the admin user's password to something other than the
default.  Don't specify the password you actually want to use in the
DEFAULT\_PASSWORD argument; arguments are stored as part of the image and it
is best to avoid letting sensitive data into them.  Simply change the password
manually once using the system within WSL or wherever you intend.

All targets user and beyond have reflector installed for easily optimizing the
pacman mirrorlist.  There's tons of ways to use this very versatile tool, but a
simple and effective way to do so is to get the fastest mirrors within your
country that have been recently updated.  One such command is:
```
reflector --country US --protocol https \
    --age 24 --fastest 10 --sort rate | sudo tee /etc/pacman.d/mirrorlist
```
Reflector has a "--save" argument where you can provide an output file path,
but because reflector DOES NOT require root privileges it's best to only give
it when writing the file.
