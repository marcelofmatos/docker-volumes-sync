#!/bin/bash
set -e

PORT=${SSH_SERVER_PORT:-22}
KEY_FILE=/tmp/sync_key

# Gerar host keys do sshd
ssh-keygen -A -q

# Gerar keypair efêmero para o cliente
ssh-keygen -t ed25519 -f "$KEY_FILE" -N "" -C "docker-volumes-sync" -q

# Adicionar chave pública ao authorized_keys do root
mkdir -p /root/.ssh
chmod 700 /root/.ssh
cat "$KEY_FILE.pub" >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
rm "$KEY_FILE.pub"

# Configurar sshd
mkdir -p /run/sshd
cat > /etc/ssh/sshd_config.d/sync.conf <<EOF
Port $PORT
PermitRootLogin yes
PubkeyAuthentication yes
PasswordAuthentication no
ChallengeResponseAuthentication no
AuthorizedKeysFile .ssh/authorized_keys
EOF

# Exibir instruções
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║         docker-volumes-sync — SERVER MODE            ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "Porta SSH: $PORT"
echo "Usuário:   root"
echo ""
echo "━━━ CHAVE PRIVADA — copie e use como SSH_PRIVATE_KEY ━━━"
cat "$KEY_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Exemplo no servidor de destino:"
echo ""
echo "  docker run -it --rm \\"
echo "    -v /var/lib/docker/volumes:/var/lib/docker/volumes \\"
echo "    -v /var/run/docker.sock:/var/run/docker.sock \\"
echo "    -e SSH_PRIVATE_KEY=\"<chave acima>\" \\"
echo "    -e ORIGEM=root@<IP_DESTE_HOST>:$PORT \\"
echo "    -e DESTINO=localhost \\"
echo "    ghcr.io/marcelofmatos/docker-volumes-sync:latest"
echo ""
echo "Servidor pronto. Aguardando conexões..."
echo ""

# Remover chave privada do filesystem (já foi exibida)
rm "$KEY_FILE"

# Iniciar sshd em foreground
exec /usr/sbin/sshd -D -e
