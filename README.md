# docker-volumes-sync

Scripts interativos para sincronizar e exportar volumes Docker entre servidores via rsync/SSH.

## Scripts disponíveis

| Script | Descrição |
|--------|-----------|
| `volumes-sync.sh` | Sincronização interativa via terminal (CLI colorido) |
| `volumes-sync-tui.sh` | Sincronização com interface visual (dialog/whiptail) |
| `volumes-export.sh` | Gera comandos de backup, restore e criação de volumes |

---

## volumes-sync.sh

Script interativo que lista volumes Docker de dois servidores e sincroniza os selecionados usando rsync.

### Instalação rápida

```bash
curl https://raw.githubusercontent.com/marcelofmatos/scripts/main/docker/volumes-sync.sh | bash
```

Ou baixar e executar:

```bash
curl https://raw.githubusercontent.com/marcelofmatos/scripts/main/docker/volumes-sync.sh > volumes-sync.sh
bash volumes-sync.sh
```

### Variáveis de ambiente

| Variável | Padrão | Descrição |
|----------|--------|-----------|
| `ORIGEM` | *(interativo)* | Servidor de origem (`usuario@ip`, alias SSH ou `localhost`) |
| `DESTINO` | *(interativo)* | Servidor de destino (`usuario@ip`, alias SSH ou `localhost`) |
| `DRY_RUN` | `true` | Simulação sem transferir arquivos |
| `VERBOSE` | `false` | Listar todos os arquivos durante a transferência |
| `DEBUG` | `false` | Apenas exibir os comandos, sem executar |
| `USE_SUDO` | `true` | Usar `sudo` para acessar os volumes Docker |

### Exemplos de uso

```bash
# Modo interativo (solicita origem e destino)
bash volumes-sync.sh

# Definir servidores por variável de ambiente
ORIGEM=usuario@azure DESTINO=usuario@hetzner bash volumes-sync.sh

# Execução real (desativa dry-run)
DRY_RUN=false ORIGEM=localhost DESTINO=usuario@hetzner bash volumes-sync.sh

# Ver arquivos transferidos
VERBOSE=true DRY_RUN=false ORIGEM=usuario@azure DESTINO=usuario@hetzner bash volumes-sync.sh

# Apenas mostrar os comandos rsync gerados
DEBUG=true ORIGEM=usuario@azure DESTINO=localhost bash volumes-sync.sh
```

### Fluxo interativo

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

## volumes-sync-tui.sh

Versão com interface visual usando `dialog` ou `whiptail`. Instala o `dialog` automaticamente se não estiver disponível.

### Instalação rápida

```bash
curl https://raw.githubusercontent.com/marcelofmatos/scripts/main/docker/volumes-sync-tui.sh | bash
```

### Funcionalidades

- Menus visuais com caixas de diálogo
- Checklist de volumes com todos pré-selecionados (desmarque os que não deseja)
- Painel de opções: DRY_RUN, VERBOSE, USE_SUDO, DEBUG
- Tela de confirmação com resumo completo
- Barra de progresso por volume
- Relatório final com tempo de execução (início, término, duração)

### Variáveis de ambiente

As mesmas do `volumes-sync.sh`: `ORIGEM`, `DESTINO`, `DRY_RUN`, `VERBOSE`, `USE_SUDO`, `DEBUG`.

---

## volumes-export.sh

Gera comandos prontos para backup, restore e recriação de volumes Docker. Útil para migrações manuais ou documentação.

### Instalação rápida

```bash
curl https://raw.githubusercontent.com/marcelofmatos/scripts/main/docker/volumes-export.sh | bash
```

### Uso

```bash
# Volumes do servidor local
bash volumes-export.sh

# Volumes de um servidor remoto
bash volumes-export.sh usuario@servidor
```

### Saída gerada

O script imprime três blocos de comandos prontos para copiar e executar:

**Backup (origem):**
```bash
mkdir -p volume-backups
docker run --rm -v meu-volume:/source:ro -v $(pwd)/volume-backups:/backup alpine \
  tar czf /backup/meu-volume.tar.gz -C /source .
```

**Restore (destino):**
```bash
docker run --rm -v meu-volume:/target -v $(pwd)/volume-backups:/backup alpine \
  tar xzf /backup/meu-volume.tar.gz -C /target
```

**Criação de volumes:**
```bash
# Volume: meu-volume (usado por: container1, container2)
docker volume create meu-volume
```

---

## Requisitos

- `bash` 4+
- `rsync` instalado em origem e destino
- `ssh` configurado com acesso sem senha (chave pública) para servidores remotos
- `docker` acessível nos servidores (com ou sem `sudo`)
- `dialog` ou `whiptail` (apenas para `volumes-sync-tui.sh` — instalado automaticamente se ausente)

## Dicas

- Configure aliases SSH em `~/.ssh/config` para que apareçam no menu interativo
- Use `DRY_RUN=true` (padrão) para validar a operação antes de transferir dados
- O modo `DEBUG=true` exibe os comandos rsync exatos sem executar nada — útil para auditoria
- Volumes inexistentes no destino são criados automaticamente antes da sincronização
