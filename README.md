# DrizellaOS

DrizellaOS è un'immagine [bootc](https://github.com/bootc-dev/bootc) personalizzata, basata su Fedora Atomic, pensata come sistema desktop immutabile con [niri](https://github.com/YaLTeR/niri) e [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell).

L'immagine viene costruita con una `Containerfile` e distribuita come immagine OCI firmata con [cosign](https://github.com/sigstore/cosign). Il progetto parte dal [template di Universal Blue](https://github.com/ublue-os/image-template).

## Caratteristiche

- **Base**: `quay.io/fedora-ostree-desktops/base-atomic:44` (Fedora Atomic senza desktop)
- **Desktop**: compositor Wayland scrollabile `niri` con shell `DankMaterialShell` (`dms`) e greeter `dms-greeter` su `greetd`
- **GPU NVIDIA**: driver open (`akmod-nvidia-open`) da RPM Fusion, compilati durante la build per il kernel dell'immagine, con initramfs rigenerato
- **Audio e rete**: PipeWire/WirePlumber, NetworkManager (Wi-Fi), Bluetooth, power-profiles-daemon
- **Applicazioni**: Firefox, Nautilus, Alacritty, Ghostty, Flatpak
- **Immagini di installazione**: configurazioni per ISO (GNOME/KDE) e dischi in `disk_config/`

## Struttura del repository

| Percorso | Contenuto |
| --- | --- |
| `Containerfile` | Definizione dell'immagine |
| `build_files/build.sh` | Script di build: kernel, driver NVIDIA, pacchetti, servizi |
| `system_files/` | File copiati nella radice (`/`) dell'immagine |
| `disk_config/` | Configurazioni per generare ISO e immagini disco |
| `Justfile` | Comandi per costruire immagini, ISO e VM in locale |
| `image-template.env` | Nome e metadati dell'immagine |
| `.github/` | Workflow GitHub Actions per build e firma |
| `INSTRUCTIONS.md` | Istruzioni originali del template per configurare il repository |

## Build locale

Servono [Podman](https://podman.io/) e [just](https://just.systems/):

```bash
just build
```

Vedi `just --list` per i comandi disponibili (ISO, immagini disco, VM).

## Installazione

Da un sistema basato su bootc (Fedora Atomic, Bazzite, Bluefin, Aurora...):

```bash
sudo bootc switch ghcr.io/<utente>/drizella-os:latest
sudo systemctl reboot
```

Sostituisci `<utente>` con il proprietario del repository GitHub che pubblica l'immagine.

## Verifica della firma

Le immagini sono firmate con cosign; la chiave pubblica è in `cosign.pub`:

```bash
cosign verify --key cosign.pub ghcr.io/<utente>/drizella-os
```

## Configurazione e setup

Per configurare GitHub Actions, la chiave di firma e il resto del flusso di lavoro, consulta [INSTRUCTIONS.md](INSTRUCTIONS.md).

## Licenza

Vedi [LICENSE](LICENSE).
