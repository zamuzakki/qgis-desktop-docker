# QGIS Desktop Docker -- plain Ubuntu build (no Nix required)
#
# This is an apt-based alternative to the Nix flake build (see flake.nix).
# It reuses the exact same runtime scripts (entrypoint.sh, start-desktop.sh)
# and config files (config/xfce4/*, config/lightdm/*) as the Nix image, so
# behaviour and environment variables are identical -- only the packaging
# mechanism differs.
#
# This file COPYs entrypoint.sh, start-desktop.sh, config/, and resources/
# from the repo root -- so the build context must be the repo root, one
# level up from this directory. Run from inside deployment/:
#
#   cd deployment
#   docker build -t qgis-desktop-docker:local -f Dockerfile ..
#   docker run --rm -p 8443:8443 --cap-add=NET_ADMIN qgis-desktop-docker:local
#
# Or just use: make build-local / make run-local (see deployment/Makefile)
#
# Targets Ubuntu 24.04 (noble). KasmVNC ships a prebuilt "noble" .deb and
# QGIS's own apt repo supports "noble" as of this writing.

FROM ubuntu:24.04

LABEL org.opencontainers.image.title="QGIS Desktop" \
      org.opencontainers.image.description="QGIS Desktop in a Docker container with KasmVNC web-based access (Ubuntu/apt build)" \
      org.opencontainers.image.url="https://github.com/kartoza/qgis-desktop-docker" \
      org.opencontainers.image.source="https://github.com/kartoza/qgis-desktop-docker" \
      org.opencontainers.image.documentation="https://github.com/kartoza/qgis-desktop-docker#readme" \
      org.opencontainers.image.vendor="Kartoza" \
      org.opencontainers.image.licenses="GPL-2.0"

ARG KASMVNC_VERSION=1.4.0
ARG UBUNTU_CODENAME=noble

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# --- Base system, X11 essentials, minimal XFCE, LightDM greeter -----------
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates wget gnupg curl xz-utils openssl \
      procps nftables iproute2 \
      dbus dbus-x11 xauth x11-xkb-utils xkb-data x11-xserver-utils \
      xfce4-session xfce4-panel xfwm4 xfce4-settings xfconf \
      xfce4-terminal xfdesktop4 thunar \
      lightdm lightdm-gtk-greeter \
      shared-mime-info hicolor-icon-theme adwaita-icon-theme \
      fonts-dejavu fonts-liberation fonts-noto-core \
    && rm -rf /var/lib/apt/lists/*

# --- QGIS (official qgis.org apt repository) -------------------------------
RUN mkdir -m755 -p /etc/apt/keyrings && \
    wget -O /etc/apt/keyrings/qgis-archive-keyring.gpg \
      https://download.qgis.org/downloads/qgis-archive-keyring.gpg && \
    printf 'Types: deb\nURIs: https://qgis.org/ubuntu\nSuites: %s\nArchitectures: amd64\nComponents: main\nSigned-By: /etc/apt/keyrings/qgis-archive-keyring.gpg\n' "${UBUNTU_CODENAME}" \
      > /etc/apt/sources.list.d/qgis.sources && \
    apt-get update && apt-get install -y --no-install-recommends qgis && \
    rm -rf /var/lib/apt/lists/*

# --- KasmVNC (prebuilt .deb, driven directly as Xkasmvnc -- no perl wrapper) -
RUN wget -O /tmp/kasmvnc.deb \
      "https://github.com/kasmtech/KasmVNC/releases/download/v${KASMVNC_VERSION}/kasmvncserver_${UBUNTU_CODENAME}_${KASMVNC_VERSION}_amd64.deb" && \
    apt-get update && apt-get install -y --no-install-recommends /tmp/kasmvnc.deb && \
    rm -f /tmp/kasmvnc.deb && \
    rm -rf /var/lib/apt/lists/*

# --- dbus needs a machine-id (no systemd in the container to generate one) -
RUN mkdir -p /var/lib/dbus && \
    dbus-uuidgen > /etc/machine-id && \
    cp /etc/machine-id /var/lib/dbus/machine-id

# --- Unprivileged desktop user ---------------------------------------------
# ubuntu:24.04 ships a default "ubuntu" user at uid/gid 1000; remove it so we
# can reuse that uid for "user" (matches VNC_USER default / the Nix image).
RUN (getent passwd ubuntu >/dev/null 2>&1 && userdel -r ubuntu >/dev/null 2>&1) || true; \
    (getent group ubuntu >/dev/null 2>&1 && groupdel ubuntu >/dev/null 2>&1) || true; \
    groupadd -g 1000 user && \
    useradd -m -u 1000 -g 1000 -s /bin/bash user && \
    mkdir -p /home/user/.vnc /home/user/.config/xfce4/panel

# --- Wallpaper + XFCE panel/desktop defaults --------------------------------
COPY resources/wallpaper.png /usr/share/wallpaper.png
COPY config/xfce4/panel/default.xml /home/user/.config/xfce4/panel/default.xml
RUN mkdir -p /etc/xdg/xfce4/xfconf/xfce-perchannel-xml
COPY config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml \
     /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml
RUN chown -R 1000:1000 /home/user

# --- LightDM (KASM_AUTH_MODE=greeter) --------------------------------------
COPY config/lightdm/lightdm.conf /etc/lightdm/lightdm.conf
COPY config/lightdm/lightdm-gtk-greeter.conf /etc/lightdm/lightdm-gtk-greeter.conf
COPY config/lightdm/xkasmvnc-wrapper.sh /etc/lightdm/xkasmvnc-wrapper
COPY config/lightdm/Xsession /etc/lightdm/Xsession
COPY config/lightdm/check-password.sh /etc/lightdm/check-password
COPY config/lightdm/xfce.desktop /usr/share/xsessions/xfce.desktop
RUN chmod 0755 /etc/lightdm/xkasmvnc-wrapper /etc/lightdm/Xsession /etc/lightdm/check-password

# Auth via pam_exec + our own check-password verifier (matches entrypoint.sh,
# which writes sha512crypt hashes into /etc/shadow with `openssl passwd -6`).
# pam_permit follows pam_exec on the auth stack so pam_setcred (called by
# lightdm before launching the session) has a module returning PAM_SUCCESS.
RUN cat > /etc/pam.d/lightdm <<'PAMEOF'
auth       required   pam_exec.so quiet expose_authtok /etc/lightdm/check-password
auth       required   pam_permit.so
account    required   pam_permit.so
password   required   pam_permit.so
session    required   pam_permit.so
session    optional   pam_env.so
PAMEOF

RUN cat > /etc/pam.d/lightdm-greeter <<'PAMEOF'
auth       required   pam_permit.so
account    required   pam_permit.so
password   required   pam_deny.so
session    required   pam_unix.so
session    optional   pam_env.so
PAMEOF

# --- Runtime scripts (shared with the Nix build) ---------------------------
COPY entrypoint.sh /usr/local/bin/qgis-entrypoint
COPY start-desktop.sh /usr/local/bin/start-desktop
RUN chmod 0755 /usr/local/bin/qgis-entrypoint /usr/local/bin/start-desktop

ENV HOME=/home/user \
    USER=user \
    VNC_USER=user \
    VNC_PW=password \
    DISPLAY=:1 \
    VNC_PORT=8443 \
    VNC_RESOLUTION=1280x720 \
    VNC_COL_DEPTH=24 \
    KASM_AUTH_MODE=basic \
    KASM_EGRESS_LOCKDOWN=1 \
    KASM_EGRESS_ALLOW= \
    XDG_RUNTIME_DIR=/tmp/runtime-user \
    XKB_DEFAULT_RULES=evdev \
    XKB_DEFAULT_MODEL=pc105 \
    XKB_DEFAULT_LAYOUT=us \
    XKB_BASE_DIR=/usr/share/X11/xkb

EXPOSE 8443/tcp

WORKDIR /home/user

# Root entrypoint sets up the nftables egress filter, then drops to UID 1000
# via setpriv before exec-ing the desktop (or execs lightdm as root when
# KASM_AUTH_MODE=greeter).
ENTRYPOINT ["/usr/local/bin/qgis-entrypoint"]
