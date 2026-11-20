# Installing DrizellaOS

DrizellaOS is a bootc image, so there are two ways to get it:

- **[Method A](#method-a-from-an-existing-fedora-atomic-system-bootc-switch)**: you already run Fedora Atomic (Silverblue, Kinoite, Sway Atomic, ...) or another bootc system (Bazzite, Bluefin, Aurora...). You only need `bootc switch`. This is the easiest path and keeps your users and data.
- **[Method B](#method-b-from-a-live-iso-bootc-install)**: you start from a blank disk and a generic Linux live ISO, and install with `bootc install to-disk`.

Then see [Upgrading](#upgrading) and [Secure Boot](#secure-boot).

The image is `ghcr.io/damimpr/drizella-os:latest` (lowercase: GHCR does not accept uppercase names).

> For the original Universal Blue template setup guide (GitHub Actions, cosign key, disk images) see [UNIVERSAL_BLUE_INSTRUCTIONS.md](UNIVERSAL_BLUE_INSTRUCTIONS.md).

## Prerequisites (both methods)

- A UEFI PC (recommended).
- Internet access: the image (a few GB) is pulled from GHCR.
- The image must be published: check that the latest GitHub Actions build succeeded.
- A **public** GHCR package, or a login with a token (see below).

---

## Method A: from an existing Fedora Atomic system (`bootc switch`)

### 1. Check where you are

```bash
sudo bootc status
```

`Booted image:` shows the image you are currently on. Any bootc-based system works; Fedora Atomic desktops are the reference case.

### 2. (Only if the package is private) Log in to GHCR

```bash
sudo podman login ghcr.io
```

Use your GitHub user and a Personal Access Token with the `read:packages` scope. Use `sudo`, because `bootc` runs as root and reads root's credentials.

### 3. (Optional) Verify the signature

The public key is `cosign.pub` in the repository:

```bash
cosign verify --key cosign.pub ghcr.io/damimpr/drizella-os:latest
```

### 4. Switch to DrizellaOS

```bash
sudo bootc switch ghcr.io/damimpr/drizella-os:latest
```

This downloads the image and stages it for the next boot. The current system is untouched until you reboot. Then:

```bash
sudo systemctl reboot
```

### 5. First login

After the reboot you get the `cosmic-greeter` login screen. Your existing users, home directories and `/etc` changes are preserved, so log in with the account you already had. Then check:

```bash
sudo bootc status
```

`Booted image:` should now be `ghcr.io/damimpr/drizella-os:latest`.

### Going back

Your previous deployment stays available as the rollback target:

```bash
sudo bootc rollback
sudo systemctl reboot
```

You can also switch back to any other image with `bootc switch <image>`.

---

## Method B: from a live ISO (`bootc install`)

This installs the image **directly on a disk**, starting from any Linux live ISO that has Podman (e.g. Fedora Workstation or Server). No intermediate Atomic system is needed.

> ⚠️ `bootc install to-disk --wipe` **erases the whole target disk**. Double-check the device.

### 1. Boot the live ISO

Boot the PC from the USB stick and choose live mode (do not install). Open a terminal and become root:

```bash
sudo -i
```

### 2. Identify the target disk

```bash
lsblk -o NAME,SIZE,MODEL,TYPE,MOUNTPOINTS
```

Note the whole device (e.g. `/dev/nvme0n1` or `/dev/sda`), **not** a partition. Do not pick the live USB stick.

### 3. (Only if the package is private) Log in to GHCR

```bash
podman login ghcr.io
```

Use your GitHub user and a Personal Access Token with the `read:packages` scope.

### 4. (Optional) Verify the signature

```bash
cosign verify --key cosign.pub ghcr.io/damimpr/drizella-os:latest
```

### 5. Create a user with sudo privileges

`bootc install` does not create users: if you install the image as is, you will have no account to log in with on first boot. So, before installing, build a small **derived image** from the live system that adds your user to the `wheel` group (on Fedora, `wheel` already has sudo).

Choose a user name and generate the password hash:

```bash
export NEW_USER=damiano                 # change to your user name
export PW_HASH="$(openssl passwd -6)"   # asks for the password twice
```

Create a `Containerfile.user` in a working folder (e.g. `mkdir ~/user && cd ~/user`):

```bash
cat > Containerfile.user <<'EOF2'
FROM ghcr.io/damimpr/drizella-os:latest

ARG NEW_USER
ARG PW_HASH

# User with bash shell and wheel group (sudo). No -m: /home is a link to /var/home,
# the home directory is created at first boot by tmpfiles.d (see below).
RUN useradd -G wheel -s /bin/bash -d "/var/home/${NEW_USER}" "${NEW_USER}" && \
    usermod -p "${PW_HASH}" "${NEW_USER}" && \
    printf 'd /var/home/%s 0700 %s %s -\n' "${NEW_USER}" "${NEW_USER}" "${NEW_USER}" \
        > /usr/lib/tmpfiles.d/10-home-"${NEW_USER}".conf
EOF2
```

Build the local image:

```bash
podman build -f Containerfile.user \
  --build-arg NEW_USER="$NEW_USER" --build-arg PW_HASH="$PW_HASH" \
  -t localhost/drizella-os-user:latest .
```

To allow passwordless `sudo` (less secure), add this to the `RUN` of `Containerfile.user`:
`echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/10-wheel-nopasswd && chmod 0440 /etc/sudoers.d/10-wheel-nopasswd`

> The password is stored in the local image as a hash (not in clear text), but the image still contains your credentials: do not publish it.

### 6. Install

Replace `/dev/nvme0n1` with the disk chosen in step 2. The installed image is the derived one, but with `--target-imgref` the system will follow the image on GHCR for updates:

```bash
podman run --rm --privileged --pid=host \
  -v /dev:/dev \
  -v /var/lib/containers:/var/lib/containers \
  --security-opt label=type:unconfined_t \
  localhost/drizella-os-user:latest \
  bootc install to-disk --wipe --filesystem xfs \
    --target-imgref ghcr.io/damimpr/drizella-os:latest \
    /dev/nvme0n1
```

Useful options:

| Option | Effect |
| --- | --- |
| `--filesystem btrfs` / `ext4` | Changes the root filesystem (image default is usually xfs) |
| `--karg=<option>` | Adds an extra kernel argument |
| `--root-ssh-authorized-keys /path/key.pub` | Adds an SSH key for `root` (emergency access) |

The NVIDIA kernel arguments (`nvidia-drm.modeset=1`, nouveau blacklist) are already in the image, in `system_files/usr/lib/bootc/kargs.d/10-nvidia.toml`.

When it finishes, power off, remove the USB stick and boot from the disk:

```bash
systemctl reboot
```

### 7. First login

Log in from the greeter (`cosmic-greeter`) with the user and password chosen in step 5. Then check your privileges:

```bash
sudo -v && sudo bootc status
```

> Steps 5 and 6 have not been tested on DrizellaOS yet: update this guide after the first test, in particular the home directory creation via `tmpfiles.d` and the effect of `--target-imgref`.

---

## Upgrading

Once installed (with either method) the system follows the image it was installed from:

```bash
sudo bootc upgrade          # pull the new image, active at next reboot
sudo bootc upgrade --check  # only check if a new image is available
sudo bootc status           # show current, staged and previous deployments
sudo systemctl reboot       # boot into the new deployment
```

If something is wrong with the new version, go back to the previous deployment:

```bash
sudo bootc rollback
sudo systemctl reboot
```

To move to another image or tag (for example a specific build):

```bash
sudo bootc switch ghcr.io/damimpr/drizella-os:<tag>
```

Images are rebuilt by GitHub Actions on every push to `main` and daily, so `bootc upgrade` regularly brings in new Fedora and NVIDIA driver updates.

## Image tags

Every build pushed to `main` (and the daily build) publishes these tags:

| Tag | Meaning |
| --- | --- |
| `latest` | Always the newest build, whatever the Fedora version |
| `v45` | Newest build based on Fedora 45 (the version comes from the `FROM` line in the `Containerfile`) |
| `v45-YYYYMMDD` | A specific day's build of Fedora 45, never moved |

Which one to follow:

- **`v45`**: stay on Fedora 45. `bootc upgrade` keeps bringing the latest builds of that release, and never jumps to a new Fedora version by surprise.
- **`latest`**: always follow the newest Fedora. When the base image moves to Fedora 46, `bootc upgrade` upgrades you automatically.

When Fedora 46 is released and the `FROM` is bumped, a new `v46` tag appears. To move from `v45` to it:

```bash
sudo bootc switch ghcr.io/damimpr/drizella-os:v46
sudo systemctl reboot
```

## Secure Boot

The NVIDIA modules are built with `akmods` at image build time and are **not signed with a key present in the firmware**. With Secure Boot enabled the NVIDIA driver will not load. Either disable Secure Boot in the firmware, or sign the modules with your own key and enroll it through a MOK.
