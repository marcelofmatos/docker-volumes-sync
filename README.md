# docker-volumes-sync

Scripts interativos para sincronizar e exportar volumes Docker entre servidores via rsync/SSH.

## Scripts disponíveis

| Script | Descrição |
|--------|-----------|
| `volumes-sync-tui.sh` | Sincronização com interface visual (dialog/whiptail) — **padrão** |
| `volumes-sync.sh` | Sincronização interativa via terminal (CLI colorido) |
| `volumes-export.sh` | Gera comandos de backup, restore e criação de volumes |

---

## Uso com Docker

A imagem está disponível no GitHub Container Registry:

```
ghcr.io/marcelofmatos/docker-volumes-sync:latest
```

> O container é interativo — sempre use as flags `-it`.

### Pull

```bash
docker pull ghcr.io/marcelofmatos/docker-volumes-sync:latest
```

### volumes-sync-tui.sh (padrão)

A forma mais simples é montar o diretório `~/.ssh` do host — todas as chaves, aliases e `known_hosts` ficam disponíveis automaticamente:

```bash
# Modo totalmente interativo
docker run -it --rm \
  -v ~/.ssh:/root/.ssh:ro \
  ghcr.io/marcelofmatos/docker-volumes-sync:latest

# Definir servidores por variável de ambiente
docker run -it --rm \
  -v ~/.ssh:/root/.ssh:ro \
  -e ORIGEM=usuario@azure \
  -e DESTINO=usuario@hetzner \
  ghcr.io/marcelofmatos/docker-volumes-sync:latest

# Execução real (desativa dry-run)
docker run -it --rm \
  -v ~/.ssh:/root/.ssh:ro \
  -e ORIGEM=usuario@azure \
  -e DESTINO=usuario@hetzner \
  -e DRY_RUN=false \
  ghcr.io/marcelofmatos/docker-volumes-sync:latest
```

> O entrypoint copia o `.ssh` para um diretório temporário gravável e corrige as permissões automaticamente, independente do tipo de chave (`id_ed25519`, `id_rsa`, `id_ecdsa`, etc.).

### volumes-sync.sh

```bash
docker run -it --rm \
  -v ~/.ssh:/root/.ssh:ro \
  ghcr.io/marcelofmatos/docker-volumes-sync:latest \
  /usr/local/bin/volumes-sync.sh
```

### volumes-export.sh

```bash
# Volumes de um servidor remoto
docker run -it --rm \
  -v ~/.ssh:/root/.ssh:ro \
  ghcr.io/marcelofmatos/docker-volumes-sync:latest \
  /usr/local/bin/volumes-export.sh usuario@servidor

# Volumes do host local (requer socket Docker montado)
docker run -it --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  ghcr.io/marcelofmatos/docker-volumes-sync:latest \
  /usr/local/bin/volumes-export.sh
```

### Acessando o host local como origem ou destino

Quando `ORIGEM` ou `DESTINO` for o próprio host que executa o container, monte o socket Docker e o diretório de volumes:

```bash
docker run -it --rm \
  -v ~/.ssh:/root/.ssh:ro \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /var/lib/docker/volumes:/var/lib/docker/volumes \
  -e ORIGEM=localhost \
  -e DESTINO=usuario@hetzner \
  -e USE_SUDO=false \
  ghcr.io/marcelofmatos/docker-volumes-sync:latest
```

O mount de `/var/lib/docker/volumes` é necessário para que o `rsync` acesse os dados dos volumes: o `docker volume inspect` retorna o caminho real no host (ex: `/var/lib/docker/volumes/meu-volume/_data`) e esse caminho precisa existir dentro do container.

> Use `USE_SUDO=false` — com o socket e o diretório de volumes montados, o container acessa o Docker e os dados diretamente sem necessidade de sudo.

### Alternativa: variáveis de ambiente

Para passar a chave sem montar o diretório SSH:

```bash
docker run -it --rm \
  -e SSH_PRIVATE_KEY="$(cat ~/.ssh/id_ed25519)" \
  -e SSH_CONFIG="$(cat ~/.ssh/config)" \
  -e ORIGEM=usuario@azure \
  -e DESTINO=usuario@hetzner \
  ghcr.io/marcelofmatos/docker-volumes-sync:latest
```

---

## Variáveis de ambiente

### Configuração SSH (entrypoint)

| Variável | Descrição |
|----------|-----------|
| `SSH_PRIVATE_KEY` | Conteúdo da chave privada SSH (gravado em `/root/.ssh/id_ed25519`) |
| `SSH_CONFIG` | Conteúdo do arquivo `~/.ssh/config` |
| `SSH_KNOWN_HOSTS` | Conteúdo do arquivo `known_hosts` |
| `SSH_STRICT_HOST_CHECKING` | `false` para desabilitar verificação de host (padrão: `true`) |

### Comportamento dos scripts

| Variável | Padrão | Descrição |
|----------|--------|-----------|
| `ORIGEM` | *(interativo)* | Servidor de origem (`usuario@ip`, alias SSH ou `localhost`) |
| `DESTINO` | *(interativo)* | Servidor de destino (`usuario@ip`, alias SSH ou `localhost`) |
| `DRY_RUN` | `true` | Simulação sem transferir arquivos |
| `VERBOSE` | `false` | Listar todos os arquivos durante a transferência |
| `DEBUG` | `false` | Apenas exibir os comandos rsync, sem executar |
| `USE_SUDO` | `true` | Usar `sudo` para acessar os volumes Docker |

---

## Fluxo interativo

1. Lista servidores disponíveis via `~/.ssh/config` + `localhost`
2. Permite selecionar origem e destino por número ou digitar manualmente
3. Testa conectividade SSH e acesso ao Docker em ambos os servidores
4. Exibe tabela comparativa dos volumes (origem vs destino)
5. Permite selecionar volumes individualmente (`1 3 5`) ou todos (`all`)
6. Pergunta se deve desativar o dry-run antes de executar
7. Exibe resumo e solicita confirmação
8. Sincroniza via rsync, criando o volume no destino se não existir
9. Exibe relatório final por volume (ok / erro / dry-run)

### Cenários suportados

| Origem | Destino | Comportamento |
|--------|---------|---------------|
| `localhost` | `localhost` | rsync local direto |
| `localhost` | remoto | rsync local → remoto via SSH |
| remoto | `localhost` | rsync remoto → local via SSH |
| remoto | remoto | rsync executado via SSH no servidor de origem |

---

## Uso sem Docker

Os scripts também podem ser executados diretamente via curl:

```bash
# volumes-sync.sh
curl https://raw.githubusercontent.com/marcelofmatos/scripts/main/docker/volumes-sync.sh | bash

# volumes-sync-tui.sh
curl https://raw.githubusercontent.com/marcelofmatos/scripts/main/docker/volumes-sync-tui.sh | bash

# volumes-export.sh
curl https://raw.githubusercontent.com/marcelofmatos/scripts/main/docker/volumes-export.sh | bash
```

### Requisitos (sem Docker)

- `bash` 4+
- `rsync` instalado em origem e destino
- `openssh-client` com acesso por chave pública para servidores remotos
- `docker` acessível nos servidores (com ou sem `sudo`)
- `dialog` ou `whiptail` (apenas para `volumes-sync-tui.sh` — instalado automaticamente se ausente)

---

## Dicas

- Configure aliases SSH em `~/.ssh/config` para que apareçam no menu interativo
- Use `DRY_RUN=true` (padrão) para validar a operação antes de transferir dados
- O modo `DEBUG=true` exibe os comandos rsync exatos sem executar nada — útil para auditoria
- Volumes inexistentes no destino são criados automaticamente antes da sincronização
- Ao usar `SSH_STRICT_HOST_CHECKING=false`, combine com `SSH_KNOWN_HOSTS` em ambientes de produção
