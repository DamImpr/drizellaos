# Installazione di DrizellaOS con `bootc install`

Questa guida installa l'immagine **direttamente su un disco**, partendo da una qualsiasi live ISO Linux con Podman (es. Fedora Workstation o Server). Non serve passare da un sistema Atomic intermedio (Silverblue, Kinoite...) né dal suo desktop.

> ⚠️ `bootc install to-disk --wipe` **cancella tutto il disco** indicato. Controlla il device due volte.

## Requisiti

- PC con UEFI (consigliato) e un disco dedicato all'installazione.
- Una live ISO Fedora (Workstation o Server vanno bene) su chiavetta USB.
- Connessione a internet: l'immagine (alcuni GB) viene scaricata da GHCR.
- L'immagine deve essere già pubblicata: controlla che l'ultima build di GitHub Actions sia andata a buon fine.
- Pacchetto GHCR **pubblico**, oppure login con un token (vedi sotto).

L'immagine è `ghcr.io/damimpr/drizella-os:latest` (nome in minuscolo: GHCR non accetta le maiuscole).

## 1. Avvia la live ISO

Avvia il PC dalla chiavetta e scegli la modalità live (senza installare). Apri un terminale e diventa root:

```bash
sudo -i
```

## 2. Identifica il disco di destinazione

```bash
lsblk -o NAME,SIZE,MODEL,TYPE,MOUNTPOINTS
```

Annota il device intero (es. `/dev/nvme0n1` o `/dev/sda`), **non** una partizione. Non usare la chiavetta della live.

## 3. (Solo se il pacchetto è privato) Login a GHCR

```bash
podman login ghcr.io
```

Usa il tuo utente GitHub e un Personal Access Token con scope `read:packages`.

## 4. (Facoltativo) Verifica la firma

La chiave pubblica è in `cosign.pub` nel repository. Se `cosign` è disponibile:

```bash
cosign verify --key cosign.pub ghcr.io/damimpr/drizella-os:latest
```

## 5. Crea l'utente con i privilegi sudo

`bootc install` non crea utenti: se installi l'immagine così com'è, al primo avvio non hai nessun account con cui entrare. Prima dell'installazione costruisci quindi, direttamente dalla live, una piccola **immagine derivata** che aggiunge l'utente e lo mette nel gruppo `wheel` (su Fedora `wheel` ha già i privilegi sudo).

Scegli nome utente e genera l'hash della password:

```bash
export NEW_USER=damiano          # cambia con il tuo nome utente
export PW_HASH="$(openssl passwd -6)"   # chiede la password due volte
```

Crea un file `Containerfile.user` in una cartella di lavoro (es. `mkdir ~/user && cd ~/user`):

```bash
cat > Containerfile.user <<'EOF2'
FROM ghcr.io/damimpr/drizella-os:latest

ARG NEW_USER
ARG PW_HASH

# Utente con shell bash e gruppo wheel (sudo). Niente -m: /home è un link a /var/home,
# la home viene creata al primo avvio da tmpfiles.d (vedi sotto).
RUN useradd -G wheel -s /bin/bash -d "/var/home/${NEW_USER}" "${NEW_USER}" && \
    usermod -p "${PW_HASH}" "${NEW_USER}" && \
    printf 'd /var/home/%s 0700 %s %s -\n' "${NEW_USER}" "${NEW_USER}" "${NEW_USER}" \
        > /usr/lib/tmpfiles.d/10-home-"${NEW_USER}".conf
EOF2
```

Costruisci l'immagine locale:

```bash
podman build -f Containerfile.user \
  --build-arg NEW_USER="$NEW_USER" --build-arg PW_HASH="$PW_HASH" \
  -t localhost/drizella-os-user:latest .
```

Se vuoi permettere `sudo` senza password (meno sicuro), aggiungi alla `RUN` del `Containerfile.user`:
`echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/10-wheel-nopasswd && chmod 0440 /etc/sudoers.d/10-wheel-nopasswd`

> La password finisce nell'immagine locale come hash (non in chiaro), ma l'immagine contiene comunque le tue credenziali: non pubblicarla.

## 6. Installa

Sostituisci `/dev/nvme0n1` con il disco scelto al punto 2. L'immagine installata è quella derivata, ma con `--target-imgref` il sistema seguirà per gli aggiornamenti l'immagine su GHCR:

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

Opzioni utili:

| Opzione | Effetto |
| --- | --- |
| `--filesystem btrfs` / `ext4` | Cambia il filesystem della root (default dell'immagine, di solito xfs) |
| `--karg=<opzione>` | Aggiunge un parametro kernel extra |
| `--root-ssh-authorized-keys /path/chiave.pub` | Inserisce una chiave SSH per `root` (accesso di emergenza) |

I parametri NVIDIA (`nvidia-drm.modeset=1`, blacklist di nouveau) sono già nell'immagine, in `system_files/usr/lib/bootc/kargs.d/10-nvidia.toml`.

Al termine, spegni, rimuovi la chiavetta e avvia dal disco:

```bash
systemctl reboot
```

## Primo accesso

Al riavvio entra dal greeter (`dms-greeter`) con l'utente e la password scelti al punto 5. Poi verifica i privilegi:

```bash
sudo -v && sudo bootc status
```

> I passaggi 5 e 6 non sono ancora stati provati su DrizellaOS: aggiorna la guida dopo il primo test, in particolare la creazione della home via `tmpfiles.d` e l'effetto di `--target-imgref`.

## Secure Boot

I moduli NVIDIA sono compilati in build con `akmods` e **non sono firmati con una chiave presente nel firmware**. Con Secure Boot attivo il driver NVIDIA non verrà caricato. Disattiva Secure Boot dal firmware, oppure firma i moduli con una tua chiave e registrala con una MOK.

## Aggiornamenti

Dopo l'installazione il sistema segue l'immagine da cui è partito:

```bash
sudo bootc upgrade          # scarica la nuova immagine, attiva al prossimo riavvio
sudo bootc status           # mostra deployment corrente, successivo e precedente
sudo bootc rollback         # torna al deployment precedente al prossimo riavvio
```

Per passare a un'altra immagine o tag: `sudo bootc switch ghcr.io/damimpr/drizella-os:<tag>`.

## Alternativa: da un sistema bootc già installato

Se hai già un sistema Fedora Atomic (Silverblue, Kinoite...) puoi evitare la live ISO e fare solo lo switch:

```bash
sudo bootc switch ghcr.io/damimpr/drizella-os:latest
sudo systemctl reboot
```
