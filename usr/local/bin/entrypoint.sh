#!/bin/bash
set -e

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

exec "$@"
