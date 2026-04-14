#!/bin/bash
#
# curl https://raw.githubusercontent.com/marcelofmatos/scripts/main/docker/volumes-sync-tui.sh | bash
#
# Script interativo com interface TUI usando gum (https://github.com/charmbracelet/gum)
#

set -eo pipefail

# Verificar dependência
if ! command -v gum &>/dev/null; then
    echo "Erro: gum não encontrado. Instale em https://github.com/charmbracelet/gum" >&2
    exit 1
fi

# Arquivos temporários
TMPLOG=$(mktemp)
TMPSCRIPT=$(mktemp --suffix=.sh)
trap "rm -f $TMPLOG $TMPSCRIPT" EXIT

# Ler configurações de variáveis de ambiente
[ -n "${DRY_RUN+x}" ] && DRY_RUN_ORIGINAL=$DRY_RUN
DRY_RUN=${DRY_RUN:-true}
DEBUG_MODE=${DEBUG:-false}
VERBOSE=${VERBOSE:-false}
ORIGEM=${ORIGEM:-""}
DESTINO=${DESTINO:-""}
USE_SUDO=${USE_SUDO:-true}

# Cores
C_TITLE="#06B6D4"
C_OK="#22C55E"
C_ERR="#EF4444"
C_WARN="#EAB308"
C_DIM="#6B7280"

# Banner
gum style \
    --foreground "$C_TITLE" --border-foreground "$C_TITLE" --border rounded \
    --align center --width 52 --margin "1 2" \
    "  Sincronização de Volumes Docker  "

# ─── Seleção de servidor ──────────────────────────────────────────────────────

selecionar_servidor() {
    local titulo=$1
    local OPCOES=("localhost")

    if [ -f "$HOME/.ssh/config" ]; then
        while IFS= read -r linha; do
            host=$(echo "$linha" | awk '{print $2}')
            [[ "$host" == *"*"* ]] && continue
            [[ "$host" == "localhost" ]] && continue
            OPCOES+=("$host")
        done < <(grep -i "^Host " "$HOME/.ssh/config" 2>/dev/null)
    fi
    OPCOES+=("Digitar manualmente...")

    gum style --foreground "$C_TITLE" --bold "$titulo"
    local ESCOLHA
    ESCOLHA=$(printf '%s\n' "${OPCOES[@]}" | gum choose \
        --cursor.foreground "$C_TITLE" \
        --item.foreground "" \
        --selected.foreground "$C_OK")

    if [ "$ESCOLHA" = "Digitar manualmente..." ]; then
        ESCOLHA=$(gum input \
            --placeholder "usuario@ip ou alias SSH" \
            --prompt "> " \
            --prompt.foreground "$C_TITLE")
        [ -z "$ESCOLHA" ] && exit 0
    fi

    echo "$ESCOLHA"
}

if [ -z "$ORIGEM" ]; then
    ORIGEM=$(selecionar_servidor "Servidor de ORIGEM:")
    [ -z "$ORIGEM" ] && exit 0
fi

if [ -z "$DESTINO" ]; then
    DESTINO=$(selecionar_servidor "Servidor de DESTINO:")
    [ -z "$DESTINO" ] && exit 0
fi

# ─── Configurar comandos Docker ───────────────────────────────────────────────

configurar_docker_cmds() {
    if [ "$ORIGEM" = "localhost" ]; then
        DOCKER_ORIGEM="$($USE_SUDO && echo 'sudo docker' || echo 'docker')"
        SSH_ORIGEM=""
    else
        DOCKER_ORIGEM="ssh $ORIGEM $($USE_SUDO && echo 'sudo docker' || echo 'docker')"
        SSH_ORIGEM="ssh $ORIGEM"
    fi
    if [ "$DESTINO" = "localhost" ]; then
        DOCKER_DESTINO="$($USE_SUDO && echo 'sudo docker' || echo 'docker')"
        SSH_DESTINO=""
    else
        DOCKER_DESTINO="ssh $DESTINO $($USE_SUDO && echo 'sudo docker' || echo 'docker')"
        SSH_DESTINO="ssh $DESTINO"
    fi
}
configurar_docker_cmds

# ─── Teste de conectividade ───────────────────────────────────────────────────

testar_conexao() {
    local servidor=$1
    local papel=$2

    if [ "$servidor" = "localhost" ]; then
        local docker_ok=false
        docker info &>/dev/null && docker_ok=true
        if ! $docker_ok; then sudo docker info &>/dev/null && docker_ok=true; fi
        if ! $docker_ok; then
            gum style --foreground "$C_ERR" "✗ Docker não acessível em localhost"
            echo "" && read -r -p "Pressione ENTER para sair..."
            exit 1
        fi
    else
        local ssh_err ssh_exit
        ssh_err=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes \
            "$servidor" exit 2>&1) && ssh_exit=0 || ssh_exit=$?

        if [ $ssh_exit -ne 0 ]; then
            echo ""
            gum style --foreground "$C_ERR" "✗ Falha na conexão SSH — $papel: $servidor"
            gum style --foreground "$C_DIM" "$ssh_err"
            echo "" && read -r -p "Pressione ENTER para sair..."
            exit 1
        fi

        local docker_ok=false
        ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$servidor" \
            "docker info" &>/dev/null && docker_ok=true
        if ! $docker_ok; then
            ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$servidor" \
                "sudo docker info" &>/dev/null && docker_ok=true
        fi
        if ! $docker_ok; then
            echo ""
            gum style --foreground "$C_ERR" "✗ Docker não acessível em $servidor"
            echo "" && read -r -p "Pressione ENTER para sair..."
            exit 1
        fi
    fi

    gum style --foreground "$C_OK" "✓ $papel: $servidor"
}

echo ""
gum style --foreground "$C_TITLE" --bold "Testando conectividade..."
gum spin --spinner dot --title " Verificando $ORIGEM..." -- \
    bash -c "ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes '$ORIGEM' exit 2>/dev/null || [ '$ORIGEM' = 'localhost' ]" \
    2>/dev/null || true
testar_conexao "$ORIGEM" "Origem"

gum spin --spinner dot --title " Verificando $DESTINO..." -- \
    bash -c "ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes '$DESTINO' exit 2>/dev/null || [ '$DESTINO' = 'localhost' ]" \
    2>/dev/null || true
testar_conexao "$DESTINO" "Destino"

# ─── Carregar volumes ─────────────────────────────────────────────────────────

echo ""
gum style --foreground "$C_TITLE" --bold "Carregando volumes..."

set +e
VOLUMES_ORIGEM=($(gum spin --spinner dot --title " Listando volumes da origem..." -- \
    bash -c "$DOCKER_ORIGEM volume ls --format '{{.Name}}' 2>/dev/null"))
VOLUMES_DESTINO=($(gum spin --spinner dot --title " Listando volumes do destino..." -- \
    bash -c "$DOCKER_DESTINO volume ls --format '{{.Name}}' 2>/dev/null"))
set -e

if [ ${#VOLUMES_ORIGEM[@]} -eq 0 ]; then
    echo ""
    gum style --foreground "$C_ERR" "✗ Nenhum volume encontrado na origem ($ORIGEM)"
    exit 1
fi

declare -A destino_volumes
for vol in "${VOLUMES_DESTINO[@]}"; do
    destino_volumes[$vol]=1
done

# ─── Seleção de volumes ───────────────────────────────────────────────────────

echo ""
gum style --foreground "$C_TITLE" --bold "Volumes disponíveis em $ORIGEM:"
gum style --foreground "$C_DIM" "TAB para selecionar • ENTER para confirmar • sem seleção = sincronizar todos"
echo ""

ITEMS=()
for vol in "${VOLUMES_ORIGEM[@]}"; do
    if [ -n "${destino_volumes[$vol]}" ]; then
        ITEMS+=("$vol  ✓")
    else
        ITEMS+=("$vol  +")
    fi
done

SELECTED=$(printf '%s\n' "${ITEMS[@]}" | gum choose --no-limit \
    --cursor.foreground "$C_TITLE" \
    --selected.foreground "$C_OK" \
    --item.foreground "" \
    --header "  ✓ existe no destino  •  + será criado") || true

VOLUMES_SELECIONADOS=()
if [ -z "$SELECTED" ]; then
    # Nenhum selecionado = sincronizar todos
    VOLUMES_SELECIONADOS=("${VOLUMES_ORIGEM[@]}")
    gum style --foreground "$C_DIM" "Nenhum volume selecionado — sincronizando todos."
else
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        vol=$(echo "$line" | sed 's/  [✓+]$//')
        VOLUMES_SELECIONADOS+=("$vol")
    done <<< "$SELECTED"
fi

# ─── Opções de sincronização ──────────────────────────────────────────────────

echo ""
gum style --foreground "$C_TITLE" --bold "Opções de sincronização:"
echo ""

if [ -z "${DRY_RUN_ORIGINAL+x}" ]; then
    gum confirm \
        --prompt.foreground "$C_WARN" \
        --selected.background "$C_WARN" \
        --unselected.foreground "$C_DIM" \
        "Executar sincronização real? (padrão: dry-run)" \
        --affirmative "Sim, executar" --negative "Não, dry-run" \
        && DRY_RUN=false || DRY_RUN=true
fi

gum confirm \
    --prompt.foreground "$C_DIM" \
    --unselected.foreground "$C_DIM" \
    "Mostrar lista de arquivos transferidos? (verbose)" \
    --affirmative "Sim" --negative "Não" \
    && VERBOSE=true || VERBOSE=false

gum confirm \
    --prompt.foreground "$C_DIM" \
    --unselected.foreground "$C_DIM" \
    "Usar sudo para acessar volumes Docker?" \
    --affirmative "Sim" --negative "Não" \
    --default=$($USE_SUDO && echo "true" || echo "false") \
    && USE_SUDO=true || USE_SUDO=false

gum confirm \
    --prompt.foreground "$C_DIM" \
    --unselected.foreground "$C_DIM" \
    "Modo debug? (apenas exibir comandos rsync, sem executar)" \
    --affirmative "Sim" --negative "Não" \
    && DEBUG_MODE=true || DEBUG_MODE=false

configurar_docker_cmds

# ─── Resumo e confirmação ─────────────────────────────────────────────────────

echo ""
gum style \
    --border rounded --border-foreground "$C_TITLE" \
    --padding "0 2" --margin "0 1" \
    "$(gum style --bold "Origem: ") $ORIGEM
$(gum style --bold "Destino:") $DESTINO
$(gum style --bold "Volumes:") ${#VOLUMES_SELECIONADOS[@]}
$(gum style --bold "Modo:   ") $($DRY_RUN && gum style --foreground "$C_WARN" "DRY-RUN (simulação)" || gum style --foreground "$C_ERR" "EXECUÇÃO REAL")
$(gum style --bold "Sudo:   ") $($USE_SUDO && echo Sim || echo Não)
$(gum style --bold "Debug:  ") $($DEBUG_MODE && echo Sim || echo Não)"
echo ""

gum confirm \
    --prompt.foreground "$C_TITLE" \
    --selected.background "$C_TITLE" \
    "Confirmar operação?" \
    --affirmative "Sim, continuar" --negative "Cancelar" \
    || exit 0

# ─── Funções de sincronização ─────────────────────────────────────────────────

get_mountpoint() {
    local docker_cmd=$1
    local volume=$2
    $docker_cmd volume inspect "$volume" --format '{{.Mountpoint}}' 2>/dev/null || echo ""
}

sync_volume() {
    local volume=$1
    local current=$2
    local total=$3
    local label="[$current/$total] $volume"

    # Mountpoint origem
    local MOUNT_ORIGEM
    if [ "$ORIGEM" = "localhost" ]; then
        MOUNT_ORIGEM=$(get_mountpoint "$DOCKER_ORIGEM" "$volume")
    else
        if $USE_SUDO; then
            MOUNT_ORIGEM=$($SSH_ORIGEM "sudo docker volume inspect $volume --format '{{.Mountpoint}}' 2>/dev/null" || echo "")
        else
            MOUNT_ORIGEM=$($SSH_ORIGEM "docker volume inspect $volume --format '{{.Mountpoint}}' 2>/dev/null" || echo "")
        fi
    fi

    if [ -z "$MOUNT_ORIGEM" ]; then
        gum style --foreground "$C_ERR" "  ✗ $label — volume não encontrado na origem"
        return 1
    fi

    # Mountpoint destino
    local MOUNT_DESTINO
    if [ "$DESTINO" = "localhost" ]; then
        MOUNT_DESTINO=$(get_mountpoint "$DOCKER_DESTINO" "$volume")
    else
        if $USE_SUDO; then
            MOUNT_DESTINO=$($SSH_DESTINO "sudo docker volume inspect $volume --format '{{.Mountpoint}}' 2>/dev/null" || echo "")
        else
            MOUNT_DESTINO=$($SSH_DESTINO "docker volume inspect $volume --format '{{.Mountpoint}}' 2>/dev/null" || echo "")
        fi
    fi

    # Criar volume no destino se não existir
    if [ -z "$MOUNT_DESTINO" ] && ! $DEBUG_MODE; then
        gum spin --spinner dot --title " $label — criando volume no destino..." -- \
            bash -c "$DOCKER_DESTINO volume create '$volume' > /dev/null"
        if [ "$DESTINO" = "localhost" ]; then
            MOUNT_DESTINO=$(get_mountpoint "$DOCKER_DESTINO" "$volume")
        else
            if $USE_SUDO; then
                MOUNT_DESTINO=$($SSH_DESTINO "sudo docker volume inspect $volume --format '{{.Mountpoint}}' 2>/dev/null")
            else
                MOUNT_DESTINO=$($SSH_DESTINO "docker volume inspect $volume --format '{{.Mountpoint}}' 2>/dev/null")
            fi
        fi
    fi

    # Opções rsync
    local RSYNC_OPTS
    if $VERBOSE; then
        RSYNC_OPTS="-avz --progress -e 'ssh -o StrictHostKeyChecking=no'"
    else
        RSYNC_OPTS="-az --info=progress2 -e 'ssh -o StrictHostKeyChecking=no'"
    fi
    $DRY_RUN    && RSYNC_OPTS="$RSYNC_OPTS --dry-run"
    $USE_SUDO   && RSYNC_OPTS="$RSYNC_OPTS --rsync-path='sudo rsync'"

    # Comando rsync conforme cenário
    local RSYNC_CMD
    if [ "$ORIGEM" = "localhost" ] && [ "$DESTINO" = "localhost" ]; then
        $USE_SUDO && RSYNC_CMD="sudo rsync $RSYNC_OPTS $MOUNT_ORIGEM/ $MOUNT_DESTINO/" \
                  || RSYNC_CMD="rsync $RSYNC_OPTS $MOUNT_ORIGEM/ $MOUNT_DESTINO/"
    elif [ "$ORIGEM" = "localhost" ]; then
        $USE_SUDO && RSYNC_CMD="sudo rsync $RSYNC_OPTS $MOUNT_ORIGEM/ $DESTINO:$MOUNT_DESTINO/" \
                  || RSYNC_CMD="rsync $RSYNC_OPTS $MOUNT_ORIGEM/ $DESTINO:$MOUNT_DESTINO/"
    elif [ "$DESTINO" = "localhost" ]; then
        $USE_SUDO && RSYNC_CMD="sudo rsync $RSYNC_OPTS $ORIGEM:$MOUNT_ORIGEM/ $MOUNT_DESTINO/" \
                  || RSYNC_CMD="rsync $RSYNC_OPTS $ORIGEM:$MOUNT_ORIGEM/ $MOUNT_DESTINO/"
    else
        $USE_SUDO && RSYNC_CMD="ssh $ORIGEM \"sudo rsync $RSYNC_OPTS $MOUNT_ORIGEM/ $DESTINO:$MOUNT_DESTINO/\"" \
                  || RSYNC_CMD="ssh $ORIGEM \"rsync $RSYNC_OPTS $MOUNT_ORIGEM/ $DESTINO:$MOUNT_DESTINO/\""
    fi

    if $DEBUG_MODE; then
        gum style --foreground "$C_WARN" "  → $label"
        gum style --foreground "$C_DIM"  "    $RSYNC_CMD"
        return 0
    fi

    # Executar via script temporário para preservar quoting
    cat > "$TMPSCRIPT" <<EOF
#!/bin/bash
eval "$RSYNC_CMD" > "$TMPLOG" 2>&1
EOF
    chmod +x "$TMPSCRIPT"

    local spin_title
    $DRY_RUN && spin_title=" $label — dry-run..." \
             || spin_title=" $label — sincronizando..."

    if gum spin --spinner dot --title "$spin_title" -- bash "$TMPSCRIPT"; then
        gum style --foreground "$C_OK" "  ✓ $label"
        if $VERBOSE; then
            gum style --foreground "$C_DIM" "$(cat "$TMPLOG")"
        fi
        return 0
    else
        gum style --foreground "$C_ERR" "  ✗ $label"
        gum style --foreground "$C_DIM" "$(cat "$TMPLOG")"
        return 1
    fi
}

# ─── Processar volumes ────────────────────────────────────────────────────────

START_TIME=$(date +%s)
START_TIME_FORMATTED=$(date '+%d/%m/%Y %H:%M:%S')
echo ""
gum style --foreground "$C_TITLE" --bold "Sincronizando volumes..."
echo ""

declare -A RESULTADO_VOLUMES
TOTAL=${#VOLUMES_SELECIONADOS[@]}
SUCESSO=0; ERROS=0

for i in "${!VOLUMES_SELECIONADOS[@]}"; do
    volume="${VOLUMES_SELECIONADOS[$i]}"
    set +e
    sync_volume "$volume" "$((i + 1))" "$TOTAL"
    STATUS=$?
    set -e
    if $DEBUG_MODE; then
        RESULTADO_VOLUMES[$volume]="debug"
    elif [ $STATUS -eq 0 ]; then
        RESULTADO_VOLUMES[$volume]="ok"
        $DRY_RUN || (( SUCESSO++ )) || true
    else
        RESULTADO_VOLUMES[$volume]="erro"
        (( ERROS++ )) || true
    fi
done

# ─── Relatório final ──────────────────────────────────────────────────────────

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
HOURS=$((ELAPSED / 3600)); MINUTES=$(((ELAPSED % 3600) / 60)); SECS=$((ELAPSED % 60))
[ $HOURS -gt 0 ]   && ELAPSED_FMT="${HOURS}h ${MINUTES}m ${SECS}s" \
|| [ $MINUTES -gt 0 ] && ELAPSED_FMT="${MINUTES}m ${SECS}s" \
|| ELAPSED_FMT="${SECS}s"

echo ""
gum style \
    --border rounded --border-foreground "$C_TITLE" \
    --padding "0 2" --margin "0 1" \
    --bold "Relatório Final"

echo ""
for volume in "${VOLUMES_SELECIONADOS[@]}"; do
    case "${RESULTADO_VOLUMES[$volume]}" in
        ok)    $DRY_RUN \
                   && gum style --foreground "$C_WARN" "  ~ $volume  (dry-run)" \
                   || gum style --foreground "$C_OK"   "  ✓ $volume" ;;
        erro)  gum style --foreground "$C_ERR"  "  ✗ $volume" ;;
        debug) gum style --foreground "$C_DIM"  "  → $volume  (debug)" ;;
    esac
done

echo ""
gum style --foreground "$C_DIM" "Início:  $START_TIME_FORMATTED"
gum style --foreground "$C_DIM" "Término: $(date '+%d/%m/%Y %H:%M:%S')"
gum style --foreground "$C_DIM" "Tempo:   $ELAPSED_FMT"

if ! $DEBUG_MODE && ! $DRY_RUN; then
    echo ""
    gum style \
        "$(gum style --foreground "$C_OK" "✓ Sucesso: $SUCESSO")  $(gum style --foreground "$C_ERR" "✗ Erros: $ERROS")  Total: $TOTAL"
fi

if $DRY_RUN; then
    echo ""
    gum style --foreground "$C_WARN" "Use DRY_RUN=false para executar a sincronização real."
fi
if $DEBUG_MODE; then
    echo ""
    gum style --foreground "$C_DIM" "Modo debug ativo — apenas comandos foram exibidos."
fi
echo ""
