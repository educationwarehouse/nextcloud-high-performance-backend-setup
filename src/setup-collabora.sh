#!/bin/bash

# Collabora Online server
# https://github.com/CollaboraOnline/online
# https://www.collaboraoffice.com/code/linux-packages/

KEYRING_URL="https://collaboraoffice.com/downloads/gpg/collaboraonline-release-keyring.gpg"
KEYRING_DIR="/usr/share/keyrings"
KEYRING_FILE="$KEYRING_DIR/collaboraonline-release-keyring.gpg"

SOURCES_FILE="/etc/apt/sources.list.d/collaboraonline.sources"
REPO_URL="https://www.collaboraoffice.com/repos/CollaboraOnline/CODE-debian$DEBIAN_MAJOR_VERSION"

TMP_DIR_PATH="tmp/collabora"

SSL_CERT_PATH="/path/to/ssl/cert"
SSL_CERT_KEY_PATH="/path/to/ssl/cert.key"

function install_collabora() {
    if [ "$SHOULD_INSTALL_COLLABORA" != true ]; then
        log "Won't install Collabora, since" \
            "\$SHOULD_INSTALL_COLLABORA is *not* true."
        return 0
    fi

    log "Installing Collabora…"

    step1
    step2
    step3
    step4
    step5
}

function step1() {
    # 1. Import the signing key
    log "\nStep 1: Import the signing key"

    cd $KEYRING_DIR
    is_dry_run || wget "$KEYRING_URL" || exit 1
    cd -
}

function step2() {
    # 2. Add CODE package repositories
    log "\nStep 2: Add CODE package repositories"

    is_dry_run || cat <<EOF >$SOURCES_FILE
Types: deb
URIs: $REPO_URL
Suites: ./
Signed-By: $KEYRING_FILE
EOF
}

function step3() {
    # 3. Install packages
    log "\nStep 3: Install packages"

    is_dry_run || apt update 2>&1 | tee -a $LOGFILE_PATH

    # Installing:
    #   - coolwsd
    #   - code-brand
    #   - nginx (for a secure ws reverse-proxy.)
    if ! is_dry_run; then
        if [ "$UNATTENTED_INSTALL" == true ]; then
            log "Trying unattented install for Collabora."
            export DEBIAN_FRONTEND=noninteractive
            apt-get install -qqy coolwsd code-brand nginx 2>&1 | tee -a $LOGFILE_PATH
        else
            apt-get install -y coolwsd code-brand nginx 2>&1 | tee -a $LOGFILE_PATH
        fi
    fi
}

function step4() {
    # 4. Prepare configuration
    log "\nStep 4: Prepare configuration"

    if ! [ -e "$TMP_DIR_PATH" ]; then
        log "Creating $TMP_DIR_PATH."
        mkdir -p "$TMP_DIR_PATH"
    else
        REPLY=""
        while ! [[ $REPLY =~ ^[YyJj]$ ]]; do
            if [ "$UNATTENTED_INSTALL" = false ]; then
                read -p "Delete * in '$TMP_DIR_PATH'? [Yy] " -n 1 -r && echo
                if [[ $REPLY =~ ^[YyJj]$ ]]; then
                    log "Deleted contents of '$TMP_DIR_PATH'."
                    rm "$TMP_DIR_PATH"/* || true
                fi
            else
                break
            fi
        done

        log "Deleted contents of '$TMP_DIR_PATH'."
        rm "$TMP_DIR_PATH"/* || true
    fi

    log "Moving Collabora config files into '$TMP_DIR_PATH'."
    cp data/collabora/* "$TMP_DIR_PATH"

    log "Preparing Collabora config files."
    log "Replacing '<HOST_FQDN>' with '$SERVER_FQDN'…"
    sed -i "s|<HOST_FQDN>|$SERVER_FQDN|g" "$TMP_DIR_PATH"/*

    log "Replacing '<SSL_CERT_PATH>' with '$SSL_CERT_PATH'…"
    sed -i "s|<SSL_CERT_PATH>|$SSL_CERT_PATH|g" "$TMP_DIR_PATH"/*

    log "Replacing '<SSL_CERT_KEY_PATH>' with '$SSL_CERT_KEY_PATH'…"
    sed -i "s|<SSL_CERT_KEY_PATH>|$SSL_CERT_KEY_PATH|g" "$TMP_DIR_PATH"/*
}

function step5() {
    # 5. Deploy configuration
    log "\nStep 5: Deploy configuration"

    deploy_file "$TMP_DIR_PATH"/collabora-server.conf /etc/nginx/sites-enabled/collabora-server.conf || true
    is_dry_run || rm /var/www/html/index.nginx-debian.html || true
    deploy_file "$TMP_DIR_PATH"/index.html /var/www/html/index.html || true
    deploy_file "$TMP_DIR_PATH"/robots.txt /var/www/html/robots.txt || true

    deploy_file "$TMP_DIR_PATH"/coolwsd.xml /etc/coolwsd/coolwsd.xml || true

    log "Deleting every '127.0.1.1' entry in /etc/hosts."
    is_dry_run || sed -i "/127.0.1.1/d" /etc/hosts

    entry="127.0.1.1 $SERVER_FQDN $(hostname)"
    log "Deploying '$entry' in /etc/hosts."
    is_dry_run || echo "$entry" >>/etc/hosts

    is_dry_run || systemctl enable --now coolwsd
    is_dry_run || systemctl enable --now nginx
    is_dry_run || systemctl enable --now janus
    is_dry_run || systemctl enable --now nats-server
}

function collabora_print_info() {
    # Just print info
    collabora_address="https://$SERVER_FQDN/"

    log "\nNow log into your Nextcloud instance with an adminstrator account" \
        "\nand navigate to Settings -> Administration -> Nextcloud Office." \
        "\nNow select 'Use your own server' and type in '$collabora_address'." \
        "\nThank you for using this script.\n"
}
