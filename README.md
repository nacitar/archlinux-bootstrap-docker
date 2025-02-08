# archlinux-bootstrap-docker
A Dockerfile that prepares an ArchLinux system from the bootstrap tarball
provided by an ArchLinux mirror.  The Dockerfile has a 'base' stage that can be
directly targeted if you JUST want a base archlinux system without any extra
configuration.

# Build Arguments
There are several build arguments that can be provided to customize the output
image, but none are required and defaults are provided in the Dockerfile.

- MIRROR\_URL: The base url of the pacman mirror to use.
(Default: "https://mnvoip.mm.fcix.net/archlinux")
- ADMIN\_USER: A sudo-enabled non-root admin user to create. (Default: tux)
- DEFAULT\_PASSWORD: The default password for the admin user. (Default:
"archlinux")
- LOCALE\_LANG: The locale to select. (Default: "en\_US.UTF-8")
- WSL\_HOSTNAME: If specified, /etc/wsl.conf will be created with the provided 
hostname entry and the default user will also be set to the ADMIN\_USER.
(Default: "")
- NO\_DOCKER\_GROUP: If specified, the admin user will not be added to the
docker group. (Default: "")
- NO\_BASHRC: If specified, [my bashrc](https://github.com/nacitar/bashrc)
won't be installed for the admin user. (Default: "")
- NO\_DEV\_TOOLS: If specified, various bash/python/c++ development tools won't
be installed. (Default: "")
- NO\_CROSS\_DEV\_TOOLS: If specified, various gcc cross-compilation toolchains
won't be installed. Automatically set if NO\_DEV\_TOOLS is specified. (Default:
"")
- NO\_NEOVIM\_CONFIG: If specified,
[my neovim config](https://github.com/nacitar/neovim-config) won't be installed
for the admin user. (Default: "")
- NO\_YAY: If specified, the AUR management utility "yay" won't be installed.
(Default: "")

# Example Usage
The simplest use case is obtaining a docker image of an ArchLinux base system:
```
docker build -t archlinux-base --target base .
```

One of the most involved use cases is creating an ArchLinux distro within WSL.
```
docker build -t wsl-archlinux \
    --build-arg WSL_HOSTNAME=archlinux --build-arg ADMIN_USER=tux \
    .
docker create --name wsl-archlinux wsl-archlinux
docker export wsl-archlinux -o wsl-archlinux.tar
docker rm wsl-archlinux
docker rmi wsl-archlinux
```


Now you'll need to import the tar file into WSL from windows.
Assuming you created C:\WSL and want your distro to be in C:\WSL\ArchLinux:
```
wsl --import ArchLinux C:\WSL\ArchLinux wsl-archlinux.tar
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

# Win32Yank
Win32Yank is an awesome tool that lets neovim (if configured properly) to yank
to/paste from the Windows clipboard.  However, there's a bug in WSL where
sometimes using this program causes wsl.exe to use 100% CPU, and over time this
happens a lot.  There's an
[issue](https://github.com/equalsraf/win32yank/issues/22) that points this
out and has a solution; place win32yank.exe somewhere on your WINDOWS
filesystem and NOT in linux.  Older versions of this Dockerfile installed this
into a the Linux filesystem, but now this feature has been removed.  It is
recommended to install this on Windows and add it to your system PATH
_ON WINDOWS_ because your Windows user's PATH is automatically included in your
PATH in WSL.  This solves the problem entirely.  I use %USERPROFILE%/bin.

You can obtain the binary from the
[releases page](https://github.com/equalsraf/win32yank/releases), downloading
win32yank-x64.zip and extracting the .exe file from it.

# Recommendations
Immediately change the admin user's password to something other than the
default.  Don't specify the password you actually want to use in the
DEFAULT\_PASSWORD argument; arguments are stored as part of the image and it
is best to avoid letting sensitive data into them.  Simply change the password
manually once using the system within WSL or wherever you intend.

Unless building with the 'base' target, reflector will be installed for easily
optimizing the pacman mirrorlist.  There's tons of ways to use this very
versatile tool, but a simple and effective way to do so is to get the fastest
mirrors within your country that have been recently updated.  One such command
is:
```
reflector --country US --protocol https \
    --age 24 --fastest 10 --sort rate | sudo tee /etc/pacman.d/mirrorlist
```
Reflector has a "--save" argument where you can provide an output file path,
but because reflector DOES NOT require root privileges it's best to only give
it when writing the file.

# Upgrading
Certain packages are installed for ONLY the admin user via "pipx", so in
addition to updating your system via pacman, in order to update those you will
need to run pipx as the admin user (*NOT root*).

In order to list packages installed via pipx, you can run `pipx list` and to
upgrade all packages installed that way you can run `pipx upgrade-all`.
