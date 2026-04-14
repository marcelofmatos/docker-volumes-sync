# docker-volumes-sync

Sincronize volumes Docker entre servidores via rsync/SSH com interface interativa.

```
ghcr.io/marcelofmatos/docker-volumes-sync:latest
```

---

## Início rápido

### Remoto → host local (caso mais comum)

```bash
docker run -it --rm \
  -v ~/.ssh:/root/.ssh:ro \
  -v /var/lib/docker/volumes:/var/lib/docker/volumes \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e DESTINO=localhost \
  ghcr.io/marcelofmatos/docker-volumes-sync:latest
```

### Modo servidor SSH (sem SSH pré-configurado na origem)

Útil quando o servidor de origem não tem SSH configurado — o container gera as chaves e expõe o servidor SSH automaticamente.

**No servidor de origem:**
```bash
docker run -d --rm \
  -v /var/lib/docker/volumes:/var/lib/docker/volumes:ro \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -p 2222:22 \
  --name dvs-server \
  ghcr.io/marcelofmatos/docker-volumes-sync:latest --server-mode
```

O log exibirá a chave privada gerada:
```
━━━ CHAVE PRIVADA — copie e use como SSH_PRIVATE_KEY ━━━
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXk...
-----END OPENSSH PRIVATE KEY-----
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**No servidor de destino** (com a chave copiada do log):
```bash
docker run -it --rm \
  -v /var/lib/docker/volumes:/var/lib/docker/volumes \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e SSH_PRIVATE_KEY="-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXk...
-----END OPENSSH PRIVATE KEY-----" \
  -e ORIGEM=root@<IP_SERVIDOR_ORIGEM>:2222 \
  -e DESTINO=localhost \
  ghcr.io/marcelofmatos/docker-volumes-sync:latest
```

> A chave é efêmera: dura apenas enquanto o container `dvs-server` estiver rodando.

---

### Entre dois servidores remotos

```bash
docker run -it --rm \
  -v ~/.ssh:/root/.ssh:ro \
  -e ORIGEM=usuario@servidor1 \
  -e DESTINO=usuario@servidor2 \
  ghcr.io/marcelofmatos/docker-volumes-sync:latest
```

### Definir origem e destino diretamente

```bash
docker run -it --rm \
  -v ~/.ssh:/root/.ssh:ro \
  -v /var/lib/docker/volumes:/var/lib/docker/volumes \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e ORIGEM=usuario@servidor \
  -e DESTINO=localhost \
  ghcr.io/marcelofmatos/docker-volumes-sync:latest
```

---

## O que faz

- Lista volumes Docker da origem e do destino, mostrando quais já existem e quais serão criados
- Permite selecionar quais volumes sincronizar (TAB) ou sincronizar todos
- Pergunta se deve executar em modo real ou dry-run antes de começar
- Testa conectividade SSH e acesso ao Docker antes de prosseguir
- Cria automaticamente o volume no destino se não existir
- Exibe progresso por volume e relatório final com status de cada um

### Variáveis de ambiente

| Variável | Padrão | Descrição |
|----------|--------|-----------|
| `ORIGEM` | *(interativo)* | Servidor de origem (`usuario@ip`, alias SSH ou `localhost`) |
| `DESTINO` | *(interativo)* | Servidor de destino (`usuario@ip`, alias SSH ou `localhost`) |
| `DRY_RUN` | `true` | Simulação sem transferir arquivos |
| `VERBOSE` | `false` | Exibir lista de arquivos durante transferência |
| `DEBUG` | `false` | Apenas exibir comandos rsync, sem executar |
| `USE_SUDO` | auto | `true` fora do container, `false` quando root |
| `SSH_SERVER_PORT` | `22` | Porta do servidor SSH no modo `--server-mode` |

---

## Detalhes

### Scripts disponíveis

| Script | Descrição |
|--------|-----------|
| `volumes-sync-tui.sh` | Interface visual com gum — **padrão** |
| `volumes-sync.sh` | CLI interativo colorido |
| `volumes-export.sh` | Gera comandos de backup/restore/criação de volumes |
| `server-mode.sh` | Inicia servidor SSH efêmero com chave gerada automaticamente |

### Cenários de sincronização

| Origem | Destino | Como sincroniza |
|--------|---------|-----------------|
| `localhost` | `localhost` | rsync local direto |
| `localhost` | remoto | rsync local → remoto via SSH |
| remoto | `localhost` | rsync remoto → local via SSH |
| remoto | remoto | rsync via SSH executado na origem |

### Mounts necessários por cenário

| Cenário | Mounts necessários |
|---------|--------------------|
| remoto → remoto | `-v ~/.ssh:/root/.ssh:ro` |
| remoto → localhost | `~/.ssh` + `/var/lib/docker/volumes` + `/var/run/docker.sock` |
| localhost → remoto | `~/.ssh` + `/var/lib/docker/volumes` + `/var/run/docker.sock` |

O mount de `/var/lib/docker/volumes` é necessário porque o `docker volume inspect` retorna o caminho real no host (ex: `/var/lib/docker/volumes/meu-volume/_data`) e o rsync precisa acessá-lo dentro do container.

### Outros scripts via Docker

```bash
# volumes-sync.sh (CLI)
docker run -it --rm \
  -v ~/.ssh:/root/.ssh:ro \
  -v /var/lib/docker/volumes:/var/lib/docker/volumes \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e DESTINO=localhost \
  ghcr.io/marcelofmatos/docker-volumes-sync:latest \
  /usr/local/bin/volumes-sync.sh

# volumes-export.sh — gerar comandos de backup/restore
docker run -it --rm \
  -v ~/.ssh:/root/.ssh:ro \
  ghcr.io/marcelofmatos/docker-volumes-sync:latest \
  /usr/local/bin/volumes-export.sh usuario@servidor
```

### Configuração SSH via variáveis de ambiente

Alternativa ao mount do `~/.ssh` — útil em pipelines CI/CD:

```bash
docker run -it --rm \
  -e SSH_PRIVATE_KEY="$(cat ~/.ssh/id_ed25519)" \
  -e SSH_CONFIG="$(cat ~/.ssh/config)" \
  -e ORIGEM=usuario@servidor \
  -e DESTINO=usuario@servidor2 \
  ghcr.io/marcelofmatos/docker-volumes-sync:latest
```

| Variável | Descrição |
|----------|-----------|
| `SSH_PRIVATE_KEY` | Conteúdo da chave privada (qualquer tipo: `id_ed25519`, `id_rsa`, etc.) |
| `SSH_CONFIG` | Conteúdo do `~/.ssh/config` |
| `SSH_KNOWN_HOSTS` | Conteúdo do `known_hosts` |
| `SSH_STRICT_HOST_CHECKING` | `false` para desabilitar verificação de host |

### Uso sem Docker

```bash
curl https://raw.githubusercontent.com/marcelofmatos/scripts/main/docker/volumes-sync-tui.sh | bash
curl https://raw.githubusercontent.com/marcelofmatos/scripts/main/docker/volumes-sync.sh | bash
curl https://raw.githubusercontent.com/marcelofmatos/scripts/main/docker/volumes-export.sh | bash
```

Requisitos: `bash` 4+, `rsync`, `openssh-client`, `docker`, [`gum`](https://github.com/charmbracelet/gum)
