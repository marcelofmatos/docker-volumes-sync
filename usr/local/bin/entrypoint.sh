#!/bin/bash
set -e

# Modo servidor SSH
if [ "$1" = "--server-mode" ]; then
    exec /usr/local/bin/server-mode.sh
fi

# Configurar SSH se chave privada for fornecida
if [ -n "$SSH_PRIVATE_KEY" ]; then
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    echo "$SSH_PRIVATE_KEY" > /root/.ssh/id_rsa
    chmod 600 /root/.ssh/id_rsa
fi

# Configurar SSH config se fornecido
if [ -n "$SSH_CONFIG" ]; then
    mkdir -p /root/.ssh
    echo "$SSH_CONFIG" > /root/.ssh/config
    chmod 600 /root/.ssh/config
fi

# Adicionar known_hosts se fornecido
if [ -n "$SSH_KNOWN_HOSTS" ]; then
    mkdir -p /root/.ssh
    echo "$SSH_KNOWN_HOSTS" > /root/.ssh/known_hosts
    chmod 644 /root/.ssh/known_hosts
fi

# Desabilitar StrictHostKeyChecking se solicitado (útil em ambientes automatizados)
if [ "${SSH_STRICT_HOST_CHECKING:-true}" = "false" ]; then
    mkdir -p /root/.ssh
    if [ ! -f /root/.ssh/config ] || ! grep -q "StrictHostKeyChecking" /root/.ssh/config; then
        echo -e "\nHost *\n    StrictHostKeyChecking no\n    UserKnownHostsFile /dev/null" >> /root/.ssh/config
        chmod 600 /root/.ssh/config
    fi
fi

# Normalizar permissões SSH
# Volumes montados como read-only não permitem chmod direto.
# Copia .ssh para /tmp/.ssh, corrige permissões e redefine HOME.
if [ -d /root/.ssh ]; then
    cp -r /root/.ssh /tmp/.ssh
    chmod 700 /tmp/.ssh
    find /tmp/.ssh -type f -name "id_*" ! -name "*.pub" -exec chmod 600 {} \; 2>/dev/null || true
    find /tmp/.ssh -type f -name "*.pub"                 -exec chmod 644 {} \; 2>/dev/null || true
    find /tmp/.ssh -type f -name "config"                -exec chmod 600 {} \; 2>/dev/null || true
    find /tmp/.ssh -type f -name "known_hosts"           -exec chmod 644 {} \; 2>/dev/null || true
    export HOME=/tmp
fi

exec "$@"
