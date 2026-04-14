#!/bin/bash

# Script para listar volumes Docker e imprimir os comandos para recriá-los e migrar dados
# Uso: 
# curl https://raw.githubusercontent.com/marcelofmatos/scripts/main/docker/volumes-export.sh | bash

REMOTE_SERVER="$1"

if [ -n "$REMOTE_SERVER" ]; then
    DOCKER_CMD="ssh $REMOTE_SERVER docker"
else
    DOCKER_CMD="docker"
fi

# Backup
echo "# ==============================="
echo "# COMANDOS PARA BACKUP DOS VOLUMES (ORIGEM)"
echo "# ==============================="
echo

echo "mkdir -p volume-backups"
$DOCKER_CMD volume ls --format "{{.Name}}" | while IFS= read -r volume_name; do
    echo "# Backup: $volume_name"
    echo "docker run --rm -v $volume_name:/source:ro -v \$(pwd)/volume-backups:/backup alpine tar czf /backup/${volume_name}.tar.gz -C /source ."
    echo

done

# Restore
echo "# ==============================="
echo "# COMANDOS PARA RESTAURAR VOLUMES (DESTINO)"
echo "# ==============================="
echo

$DOCKER_CMD volume ls --format "{{.Name}}" | while IFS= read -r volume_name; do
    echo "# Restore: $volume_name"
    echo "docker run --rm -v $volume_name:/target -v \$(pwd)/volume-backups:/backup alpine tar xzf /backup/${volume_name}.tar.gz -C /target"
    echo

done


# Cabeçalhos
echo "# ==============================="
echo "# COMANDOS PARA CRIAR VOLUMES"
echo "# ==============================="
echo

$DOCKER_CMD volume ls --format "{{.Name}}" | while IFS= read -r volume_name; do
    driver=$($DOCKER_CMD volume inspect "$volume_name" --format '{{.Driver}}' 2>/dev/null)
    containers=$($DOCKER_CMD ps -a --filter volume="$volume_name" --format "{{.Names}}" 2>/dev/null | tr '\n' ', ' | sed 's/,$//')

    if [ -n "$containers" ]; then
        echo "# Volume: $volume_name (usado por: $containers)"
    else
        echo "# Volume: $volume_name"
    fi

    if [ "$driver" = "local" ] || [ -z "$driver" ]; then
        echo "docker volume create $volume_name"
    else
        echo "docker volume create --driver $driver $volume_name"
    fi
    echo

done
