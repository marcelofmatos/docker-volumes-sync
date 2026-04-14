#!/bin/bash
#
# curl https://raw.githubusercontent.com/marcelofmatos/scripts/main/docker/volumes-sync-tui.sh | bash
#
# Script interativo com interface TUI usando gum (https://github.com/charmbracelet/gum)
# Opções via variáveis de ambiente: DRY_RUN, VERBOSE, DEBUG, USE_SUDO, ORIGEM, DESTINO
#

set -eo pipefail

if ! command -v gum &>/dev/null; then
    echo "Erro: gum não encontrado. Instale em https://github.com/charmbracelet/gum" >&2
    exit 1
fi

TMPLOG=$(mktemp)
TMPSCRIPT=$(mktemp --suffix=.sh)
TMPVOL_ORIG=$(mktemp)
TMPVOL_DEST=$(mktemp)
trap "rm -f $TMPLOG $TMPSCRIPT $TMPVOL_ORIG $TMPVOL_DEST" EXIT

[ -n "${DRY_RUN+x}" ] && DRY_RUN_ORIGINAL=$DRY_RUN
DRY_RUN=${DRY_RUN:-true}
DEBUG_MODE=${DEBUG:-false}
VERBOSE=${VERBOSE:-false}
ORIGEM=${ORIGEM:-""}
DESTINO=${DESTINO:-""}
# Desabilitar sudo automaticamente quando rodando como root
[ "$(id -u)" = "0" ] && USE_SUDO_DEFAULT=false || USE_SUDO_DEFAULT=true
USE_SUDO=${USE_SUDO:-$USE_SUDO_DEFAULT}

C_TITLE="#06B6D4"
C_OK="#22C55E"
C_ERR="#EF4444"
C_WARN="#EAB308"
C_DIM="#6B7280"

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
        ESCOLHA=$(gum input --placeholder "usuario@ip ou alias SSH" \
            --prompt "> " --prompt.foreground "$C_TITLE")
        [ -z "$ESCOLHA" ] && exit 0
    fi

    echo "$ESCOLHA"
}

[ -z "$ORIGEM"  ] && { ORIGEM=$(selecionar_servidor  "Origem:"); [ -z "$ORIGEM"  ] && exit 0; }
[ -z "$DESTINO" ] && { DESTINO=$(selecionar_servidor "Destino:"); [ -z "$DESTINO" ] && exit 0; }

# ─── Configurar comandos Docker ───────────────────────────────────────────────

configurar_docker_cmds() {
    if [ "$ORIGEM" = "localhost" ]; then
        DOCKER_ORIGEM="$($USE_SUDO && echo 'sudo docker' || echo 'docker')"; SSH_ORIGEM=""
    else
        DOCKER_ORIGEM="ssh $ORIGEM $($USE_SUDO && echo 'sudo docker' || echo 'docker')"
        SSH_ORIGEM="ssh $ORIGEM"
    fi
    if [ "$DESTINO" = "localhost" ]; then
        DOCKER_DESTINO="$($USE_SUDO && echo 'sudo docker' || echo 'docker')"; SSH_DESTINO=""
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
        gum style --foreground "$C_OK" "✓ $papel: localhost"
        return 0
    fi

    local ssh_err ssh_exit
    ssh_err=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes \
        "$servidor" exit 2>&1) && ssh_exit=0 || ssh_exit=$?

    if [ $ssh_exit -ne 0 ]; then
        gum style --foreground "$C_ERR" "✗ Falha SSH — $papel: $servidor"
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
        gum style --foreground "$C_ERR" "✗ Docker não acessível em $servidor"
        echo "" && read -r -p "Pressione ENTER para sair..."
        exit 1
    fi

    gum style --foreground "$C_OK" "✓ $papel: $servidor"
}

echo ""
[ "$ORIGEM"  != "localhost" ] && gum spin --spinner dot --title " Verificando $ORIGEM..."  -- \
    bash -c "ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes '$ORIGEM' exit" \
    2>/dev/null || true
testar_conexao "$ORIGEM" "Origem"

[ "$DESTINO" != "localhost" ] && gum spin --spinner dot --title " Verificando $DESTINO..." -- \
    bash -c "ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes '$DESTINO' exit" \
    2>/dev/null || true
testar_conexao "$DESTINO" "Destino"

# ─── Carregar volumes ─────────────────────────────────────────────────────────

echo ""
set +e
gum spin --spinner dot --title " Carregando volumes da origem..." -- \
    bash -c "$DOCKER_ORIGEM volume ls --format '{{.Name}}' > '$TMPVOL_ORIG' 2>/dev/null"
gum spin --spinner dot --title " Carregando volumes do destino..." -- \
    bash -c "$DOCKER_DESTINO volume ls --format '{{.Name}}' > '$TMPVOL_DEST' 2>/dev/null"
VOLUMES_ORIGEM=($(cat "$TMPVOL_ORIG"))
VOLUMES_DESTINO=($(cat "$TMPVOL_DEST"))
set -e

if [ ${#VOLUMES_ORIGEM[@]} -eq 0 ]; then
    gum style --foreground "$C_ERR" "✗ Nenhum volume encontrado na origem ($ORIGEM)"
    exit 1
fi

declare -A destino_volumes
for vol in "${VOLUMES_DESTINO[@]}"; do destino_volumes[$vol]=1; done

# ─── Seleção de volumes ───────────────────────────────────────────────────────

COUNT_EXIST=0; COUNT_NEW=0
ITEMS_EXIST=(); ITEMS_NEW=()
for vol in "${VOLUMES_ORIGEM[@]}"; do
    if [ -n "${destino_volumes[$vol]}" ]; then
        ITEMS_EXIST+=("$vol  ✓"); (( COUNT_EXIST++ )) || true
    else
        ITEMS_NEW+=("$vol  +");  (( COUNT_NEW++   )) || true
    fi
done
ITEMS=("${ITEMS_EXIST[@]}" "${ITEMS_NEW[@]}")

COUNT_DEST=${#VOLUMES_DESTINO[@]}
echo ""
gum style --foreground "$C_DIM" \
    "origem: $(gum style --foreground "$C_TITLE" "${#VOLUMES_ORIGEM[@]}")  •  destino: $(gum style --foreground "$C_TITLE" "$COUNT_DEST")  •  em comum: $(gum style --foreground "$C_OK" "$COUNT_EXIST")  •  TAB seleciona • ENTER confirma • sem seleção = todos"
echo ""

SELECTED=$(printf '%s\n' "${ITEMS[@]}" | gum choose --no-limit \
    --cursor.foreground "$C_TITLE" \
    --selected.foreground "$C_OK" \
    --item.foreground "" \
    --header "  $ORIGEM  →  $DESTINO$($DRY_RUN && echo '  [dry-run]' || true)") || true

VOLUMES_SELECIONADOS=()
if [ -z "$SELECTED" ]; then
    VOLUMES_SELECIONADOS=("${VOLUMES_ORIGEM[@]}")
else
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        VOLUMES_SELECIONADOS+=("$(echo "$line" | sed 's/  [✓+]$//')")
    done <<< "$SELECTED"
fi

# ─── Sincronização ────────────────────────────────────────────────────────────

get_mountpoint() {
    local docker_cmd=$1 volume=$2
    $docker_cmd volume inspect "$volume" --format '{{.Mountpoint}}' 2>/dev/null || echo ""
}

sync_volume() {
    local volume=$1 current=$2 total=$3
    local label="[$current/$total] $volume"

    local MOUNT_ORIGEM MOUNT_DESTINO
    if [ "$ORIGEM" = "localhost" ]; then
        MOUNT_ORIGEM=$(get_mountpoint "$DOCKER_ORIGEM" "$volume")
    else
        $USE_SUDO \
            && MOUNT_ORIGEM=$($SSH_ORIGEM "sudo docker volume inspect $volume --format '{{.Mountpoint}}' 2>/dev/null" || echo "") \
            || MOUNT_ORIGEM=$($SSH_ORIGEM "docker volume inspect $volume --format '{{.Mountpoint}}' 2>/dev/null" || echo "")
    fi

    if [ -z "$MOUNT_ORIGEM" ]; then
        gum style --foreground "$C_ERR" "  ✗ $label — volume não encontrado na origem"
        return 1
    fi

    if [ "$DESTINO" = "localhost" ]; then
        MOUNT_DESTINO=$(get_mountpoint "$DOCKER_DESTINO" "$volume")
    else
        $USE_SUDO \
            && MOUNT_DESTINO=$($SSH_DESTINO "sudo docker volume inspect $volume --format '{{.Mountpoint}}' 2>/dev/null" || echo "") \
            || MOUNT_DESTINO=$($SSH_DESTINO "docker volume inspect $volume --format '{{.Mountpoint}}' 2>/dev/null" || echo "")
    fi

    if [ -z "$MOUNT_DESTINO" ] && ! $DEBUG_MODE; then
        gum spin --spinner dot --title " $label — criando volume..." -- \
            bash -c "$DOCKER_DESTINO volume create '$volume' > /dev/null"
        if [ "$DESTINO" = "localhost" ]; then
            MOUNT_DESTINO=$(get_mountpoint "$DOCKER_DESTINO" "$volume")
        else
            $USE_SUDO \
                && MOUNT_DESTINO=$($SSH_DESTINO "sudo docker volume inspect $volume --format '{{.Mountpoint}}' 2>/dev/null") \
                || MOUNT_DESTINO=$($SSH_DESTINO "docker volume inspect $volume --format '{{.Mountpoint}}' 2>/dev/null")
        fi
    fi

    local RSYNC_OPTS
    $VERBOSE && RSYNC_OPTS="-avz --progress -e 'ssh -o StrictHostKeyChecking=no'" \
             || RSYNC_OPTS="-az --info=progress2 -e 'ssh -o StrictHostKeyChecking=no'"
    $DRY_RUN  && RSYNC_OPTS="$RSYNC_OPTS --dry-run"
    $USE_SUDO && RSYNC_OPTS="$RSYNC_OPTS --rsync-path='sudo rsync'"

    local RSYNC_CMD
    if   [ "$ORIGEM" = "localhost" ] && [ "$DESTINO" = "localhost" ]; then
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

    cat > "$TMPSCRIPT" <<EOF
#!/bin/bash
eval "$RSYNC_CMD" > "$TMPLOG" 2>&1
EOF
    chmod +x "$TMPSCRIPT"

    local spin_title=" $label$($DRY_RUN && echo ' — dry-run...' || echo ' — sincronizando...')"
    if gum spin --spinner dot --title "$spin_title" -- bash "$TMPSCRIPT"; then
        gum style --foreground "$C_OK" "  ✓ $label"
        $VERBOSE && gum style --foreground "$C_DIM" "$(cat "$TMPLOG")" || true
        return 0
    else
        gum style --foreground "$C_ERR" "  ✗ $label"
        gum style --foreground "$C_DIM" "$(cat "$TMPLOG")"
        return 1
    fi
}

# ─── Processar ───────────────────────────────────────────────────────────────

START_TIME=$(date +%s)
echo ""
TOTAL=${#VOLUMES_SELECIONADOS[@]}
declare -A RESULTADO_VOLUMES
SUCESSO=0; ERROS=0

for i in "${!VOLUMES_SELECIONADOS[@]}"; do
    volume="${VOLUMES_SELECIONADOS[$i]}"
    set +e; sync_volume "$volume" "$((i + 1))" "$TOTAL"; STATUS=$?; set -e
    if $DEBUG_MODE; then
        RESULTADO_VOLUMES[$volume]="debug"
    elif [ $STATUS -eq 0 ]; then
        RESULTADO_VOLUMES[$volume]="ok"; $DRY_RUN || (( SUCESSO++ )) || true
    else
        RESULTADO_VOLUMES[$volume]="erro"; (( ERROS++ )) || true
    fi
done

# ─── Relatório ───────────────────────────────────────────────────────────────

ELAPSED=$(( $(date +%s) - START_TIME ))
HOURS=$((ELAPSED/3600)); MINS=$(((ELAPSED%3600)/60)); SECS=$((ELAPSED%60))
[ $HOURS -gt 0 ] && TFMT="${HOURS}h ${MINS}m ${SECS}s" \
|| [ $MINS -gt 0 ] && TFMT="${MINS}m ${SECS}s" || TFMT="${SECS}s"

echo ""
gum style --foreground "$C_TITLE" --bold "Relatório  •  $ORIGEM → $DESTINO  •  $TFMT"
echo ""

for volume in "${VOLUMES_SELECIONADOS[@]}"; do
    case "${RESULTADO_VOLUMES[$volume]}" in
        ok)    $DRY_RUN \
                   && gum style --foreground "$C_WARN" "  ~ $volume" \
                   || gum style --foreground "$C_OK"   "  ✓ $volume" ;;
        erro)  gum style --foreground "$C_ERR" "  ✗ $volume" ;;
        debug) gum style --foreground "$C_DIM" "  → $volume" ;;
    esac
done

echo ""
if ! $DEBUG_MODE && ! $DRY_RUN; then
    gum style "$(gum style --foreground "$C_OK" "✓ $SUCESSO ok")  $(gum style --foreground "$C_ERR" "✗ $ERROS erro")  total $TOTAL"
fi
$DRY_RUN  && gum style --foreground "$C_WARN" "dry-run — use DRY_RUN=false para sincronizar"
$DEBUG_MODE && gum style --foreground "$C_DIM" "debug — apenas comandos exibidos"
echo ""
