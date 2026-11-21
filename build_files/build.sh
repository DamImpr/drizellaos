#!/bin/bash
set -ouex pipefail

# Copia system_files/ in /
cp -avf "/ctx/system_files"/. /

########################################
# 0. Prerequisiti per immagini ostree-based
########################################
mkdir -p /var/roothome
if ! rpm -q dnf5 dnf5-plugins >/dev/null 2>&1; then
    rpm-ostree install dnf5 dnf5-plugins
fi

########################################
# 1. Kernel: serve kernel-devel IDENTICO al kernel dell'immagine, e UN solo kernel
#    (bootc container lint fallisce con più kernel)
########################################
kver() { rpm -q kernel-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort -V | tail -1; }
KVER=$(kver)

if ! dnf5 -y install "kernel-devel-${KVER}"; then
    # L'immagine ha un kernel più vecchio di quello nei repo: aggiorna il kernel.
    # Durante l'install di un kernel in container gli hook rpm-ostree/dracut possono
    # fallire, quindi li disattiviamo temporaneamente (stesso trucco di Universal Blue).
    pushd /usr/lib/kernel/install.d
    for h in 05-rpmostree.install 50-dracut.install; do
        [ -e "$h" ] && mv "$h" "$h.bak" && printf '%s\n' '#!/bin/sh' 'exit 0' > "$h" && chmod +x "$h"
    done
    popd
    dnf5 -y upgrade 'kernel*'
    pushd /usr/lib/kernel/install.d
    for h in 05-rpmostree.install 50-dracut.install; do
        [ -e "$h.bak" ] && mv -f "$h.bak" "$h"
    done
    popd

    NEW=$(kver)
    # Rimuovi i kernel vecchi
    for v in $(rpm -q kernel-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' | grep -vx "$NEW" || true); do
        rpm -qa 'kernel*' | grep -F -- "$v" | xargs -r rpm --erase --nodeps
    done
    KVER="$NEW"
    dnf5 -y install "kernel-devel-${KVER}"
fi

########################################
# 2. RPM Fusion + driver NVIDIA open Turing
########################################
dnf5 -y install \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

dnf5 -y install akmods gcc make

# Il %post del pacchetto prova a compilare per il kernel dell'HOST e può fallire: va bene,
# compiliamo noi per il kernel dell'immagine subito dopo.
# Da F45 RPM Fusion non ha più akmod-nvidia-open: akmod-nvidia è già open-only (driver >= 590).
if dnf5 -q repoquery akmod-nvidia-open 2>/dev/null | grep -q .; then
    AKMOD=akmod-nvidia-open
else
    AKMOD=akmod-nvidia
fi
dnf5 -y install "$AKMOD" xorg-x11-drv-nvidia xorg-x11-drv-nvidia-libs \
    nvidia-settings libva-nvidia-driver || true
rpm -q "$AKMOD" xorg-x11-drv-nvidia   # fallisce la build se non installati

akmods --force --kernels "${KVER}"
# Verifica che il modulo esista davvero
find "/usr/lib/modules/${KVER}" -name 'nvidia*.ko*' | grep -q .

# Initramfs con il modulo incluso (su immagini ostree serve --add ostree)
export DRACUT_NO_XATTR=1
dracut --no-hostonly --kver "${KVER}" --reproducible --add ostree -f "/usr/lib/modules/${KVER}/initramfs.img"
chmod 0600 "/usr/lib/modules/${KVER}/initramfs.img"

# NB: non rimuovo gcc/make/kernel-devel: akmod-nvidia-open li richiede e una rimozione
# a cascata porterebbe via anche il driver.

########################################
# 3. Base desktop minima (fedora-bootc è senza grafica)
########################################
dnf5 install -y \
    linux-firmware \
    mesa-dri-drivers mesa-libgbm mesa-libEGL mesa-vulkan-drivers \
    xorg-x11-server-Xwayland \
    pipewire pipewire-pulseaudio wireplumber \
    NetworkManager-wifi bluez power-profiles-daemon upower accountsservice \
    flatpak sudo xdg-user-dirs git vim-enhanced fastfetch \
    gnupg2 pinentry-qt \
    google-noto-sans-fonts google-noto-emoji-fonts

########################################
# NOTA: siamo passati a COSMIC. La configurazione niri + DankMaterialShell
# (vecchi stage 4-6) è lasciata qui sotto commentata come riferimento.
########################################
# ########################################
# # 4. niri + DankMaterialShell (COPR abilitato solo in build)
# ########################################
# dnf5 -y copr enable avengemedia/dms
#
# dnf5 install -y \
#     niri \
#     dms \
#     dms-greeter \
#     greetd \
#     xdg-desktop-portal-gnome \
#     xdg-desktop-portal-gtk \
#     gnome-keyring \
#     polkit \
#     nautilus \
#     alacritty \
#     firefox
#
# dnf5 install -y --skip-unavailable \
#     xwayland-satellite \
#     ghostty \
#     pavucontrol \
#     fira-code-fonts
#
# dnf5 -y copr disable avengemedia/dms
#
# ########################################
# # 5. Servizi
# ########################################
# systemctl enable greetd.service
# systemctl enable bluetooth.service
# systemctl enable power-profiles-daemon.service
# systemctl enable NetworkManager.service
# systemctl set-default graphical.target
# # Avvia DMS insieme a niri (equivale a `systemctl --user add-wants niri.service dms`)
# systemctl --global add-wants niri.service dms.service
#
# ########################################
# # 6. Configurazione greetd -> dms-greeter (scritta dopo l'install dei pacchetti,
# #    così il file di default di greetd non la sovrascrive)
# ########################################
# mkdir -p /etc/greetd
# cat > /etc/greetd/config.toml <<'EOF'
# [terminal]
# vt = 1
#
# [default_session]
# user = "greeter"
# command = "/usr/bin/dms-greeter --command niri"
# EOF

########################################
# NOTA: siamo passati a KDE Plasma. La configurazione COSMIC (vecchi stage 4-5)
# è lasciata qui sotto commentata come riferimento.
########################################
# ########################################
# # 4. COSMIC desktop (dai repo Fedora, nessun COPR)
# ########################################
# dnf5 install -y @cosmic-desktop-environment
#
# dnf5 install -y --skip-unavailable \
#     xdg-desktop-portal-cosmic \
#     pavucontrol \
#     firefox \
#     fira-code-fonts
#
# ########################################
# # 5. Servizi
# ########################################
# systemctl enable cosmic-greeter.service
# systemctl enable bluetooth.service
# systemctl enable power-profiles-daemon.service
# systemctl enable NetworkManager.service
# systemctl set-default graphical.target

########################################
# 4. KDE Plasma (dai repo Fedora, nessun COPR)
########################################
dnf5 install -y @kde-desktop-environment

dnf5 install -y --skip-unavailable \
    xdg-desktop-portal-kde \
    firefox \
    fira-code-fonts

########################################
# 5. Virtualizzazione: libvirt + QEMU/KVM + virt-manager
########################################
dnf5 install -y \
    qemu-kvm \
    libvirt \
    virt-manager \
    virt-install \
    virt-viewer \
    edk2-ovmf \
    swtpm

########################################
# 6. Servizi
########################################
# Login manager: da Fedora 44 KDE usa plasma-login-manager al posto di SDDM;
# abilito quello presente nell'immagine e fallisco la build se non ce n'è nessuno.
if [ -e /usr/lib/systemd/system/plasmalogin.service ]; then
    systemctl enable plasmalogin.service
elif [ -e /usr/lib/systemd/system/sddm.service ]; then
    systemctl enable sddm.service
else
    echo "Nessun login manager KDE trovato" >&2
    exit 1
fi
systemctl enable bluetooth.service
systemctl enable power-profiles-daemon.service
systemctl enable NetworkManager.service
# libvirt modulare (default su Fedora): attivazione via socket
for d in virtqemud virtnetworkd virtstoraged virtnodedevd virtsecretd virtinterfaced virtnwfilterd; do
    systemctl enable "${d}.socket"
done
systemctl set-default graphical.target

########################################
# 7. Branding: nome OS "Drizella OS" (ID=fedora resta per compatibilità con RPM Fusion/COPR)
########################################
sed -i -e '/^NAME=/d' -e '/^PRETTY_NAME=/d' -e '/^LOGO=/d' /usr/lib/os-release
cat >> /usr/lib/os-release <<'EOF'
NAME="Drizella OS"
PRETTY_NAME="Drizella OS"
EOF
