# DrizellaOS

DrizellaOS is a custom [bootc](https://github.com/bootc-dev/bootc) image based on Fedora Atomic, designed as an immutable desktop system with [niri](https://github.com/YaLTeR/niri) and [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell).

The image is built from a `Containerfile` and distributed as an OCI image signed with [cosign](https://github.com/sigstore/cosign). The project starts from the [Universal Blue template](https://github.com/ublue-os/image-template).

## Features

- **Base**: `quay.io/fedora-ostree-desktops/base-atomic:45` (Fedora Atomic without a desktop)
- **Desktop**: `niri` scrollable Wayland compositor with the `DankMaterialShell` (`dms`) shell and the `dms-greeter` greeter on `greetd`
- **NVIDIA GPU**: open drivers (`akmod-nvidia-open`, or `akmod-nvidia` from F45) from RPM Fusion, compiled at build time for the image kernel, with a regenerated initramfs
- **Audio and network**: PipeWire/WirePlumber, NetworkManager (Wi-Fi), Bluetooth, power-profiles-daemon
- **Applications**: Firefox, Nautilus, Alacritty, Ghostty, Flatpak, fastfetch (with a custom "D OS" logo)
- **Install images**: ISO (GNOME/KDE) and disk configurations in `disk_config/`

## Repository layout

| Path | Contents |
| --- | --- |
| `Containerfile` | Image definition |
| `build_files/build.sh` | Build script: kernel, NVIDIA driver, packages, services |
| `system_files/` | Files copied onto the image root (`/`) |
| `disk_config/` | Configurations to generate ISOs and disk images |
| `Justfile` | Commands to build images, ISOs and VMs locally |
| `image-template.env` | Image name and metadata |
| `.github/` | GitHub Actions workflows for build and signing |
| `INSTRUCTIONS.md` | DrizellaOS installation and upgrade guide |
| `UNIVERSAL_BLUE_INSTRUCTIONS.md` | Original Universal Blue template guide for setting up the repository |

## Local build

Requires [Podman](https://podman.io/) and [just](https://just.systems/):

```bash
just build
```

See `just --list` for the available commands (ISO, disk images, VM).

## Installation

The full guide is in [INSTRUCTIONS.md](INSTRUCTIONS.md). It covers installing from an existing Fedora Atomic system with `bootc switch`, installing from a live ISO with `bootc install`, and upgrading.

Quick version, from a bootc-based system (Fedora Atomic, Bazzite, Bluefin, Aurora...):

```bash
sudo bootc switch ghcr.io/damimpr/drizella-os:latest
sudo systemctl reboot
```

Later, to upgrade:

```bash
sudo bootc upgrade
sudo systemctl reboot
```

## Signature verification

Images are signed with cosign; the public key is in `cosign.pub`:

```bash
cosign verify --key cosign.pub ghcr.io/damimpr/drizella-os
```

## Configuration and setup

To set up GitHub Actions, the signing key and the rest of the workflow, see [UNIVERSAL_BLUE_INSTRUCTIONS.md](UNIVERSAL_BLUE_INSTRUCTIONS.md).

## License

See [LICENSE](LICENSE).
