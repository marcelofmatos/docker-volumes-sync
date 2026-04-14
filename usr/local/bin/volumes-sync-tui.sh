#!/bin/bash
#
# curl https://raw.githubusercontent.com/marcelofmatos/scripts/main/docker/volumes-sync-tui.sh | bash
#
# Script interativo com interface TUI usando dialog/whiptail
#

set -eo pipefail

# Verificar dependências
if command -v dialog &> /dev/null; then
    DIALOG=dialog
elif command -v whiptail &> /dev/null; then
    DIALOG=whiptail
else
    echo "Instalando dialog..."
    sudo apt-get update && sudo apt-get install -y dialog
    DIALOG=dialog
fi

# Variáveis
TEMPFILE=$(mktemp)
TMPLOG=$(mktemp)
trap "rm -f $TEMPFILE $TMPLOG" EXIT

# Ler configurações de variáveis de ambiente
[ -n "${DRY_RUN+x}" ] && DRY_RUN_ORIGINAL=$DRY_RUN
DRY_RUN=${DRY_RUN:-true}
DEBUG_MODE=${DEBUG:-false}
VERBOSE=${VERBOSE:-false}
ORIGEM=${ORIGEM:-""}
DESTINO=${DESTINO:-""}
USE_SUDO=${USE_SUDO:-true}

# Banner inicial
$DIALOG --title "Sincronização de Volumes Docker" \
    --msgbox "Bem-vindo ao assistente de sincronização\n\nEste script irá ajudá-lo a transferir volumes Docker entre servidores de forma segura." 12 60

# Função para montar menu de servidores a partir do ~/.ssh/config
selecionar_servidor() {
    local titulo=$1
    local MENU_ITEMS=()

    MENU_ITEMS+=("localhost" "Máquina local")

    if [ -f "$HOME/.ssh/config" ]; then
        while IFS= read -r linha; do
            host=$(echo "$linha" | awk '{print $2}')
            [[ "$host" == *"*"* ]] && continue
            [[ "$host" == "localhost" ]] && continue
            MENU_ITEMS+=("$host" "Host SSH")
        done < <(grep -i "^Host " "$HOME/.ssh/config" 2>/dev/null)
    fi

    MENU_ITEMS+=("__manual__" "Digitar manualmente...")

    $DIALOG --title "$titulo" \
        --menu "Selecione o servidor:" 20 60 12 \
        "${MENU_ITEMS[@]}" 2>$TEMPFILE

    local ESCOLHA
    ESCOLHA=$(cat $TEMPFILE)

    if [ "$ESCOLHA" = "__manual__" ]; then
        $DIALOG --title "$titulo" \
            --inputbox "Digite o endereço do servidor\n(ex: usuario@ip ou alias SSH):" 10 60 2>$TEMPFILE
        ESCOLHA=$(cat $TEMPFILE)
        [ -z "$ESCOLHA" ] && exit 0
    fi

    echo "$ESCOLHA"
}

# Solicitar servidores
if [ -z "$ORIGEM" ]; then
    ORIGEM=$(selecionar_servidor "Servidor de Origem")
    [ -z "$ORIGEM" ] && exit 0
fi

if [ -z "$DESTINO" ]; then
    DESTINO=$(selecionar_servidor "Servidor de Destino")
    [ -z "$DESTINO" ] && exit 0
fi

# Configurar comandos Docker
if [ "$ORIGEM" = "localhost" ]; then
    DOCKER_ORIGEM="$( $USE_SUDO && echo 'sudo docker' || echo 'docker' )"
    SSH_ORIGEM=""
else
    DOCKER_ORIGEM="ssh $ORIGEM $( $USE_SUDO && echo 'sudo docker' || echo 'docker' )"
    SSH_ORIGEM="ssh $ORIGEM"
fi

if [ "$DESTINO" = "localhost" ]; then
    DOCKER_DESTINO="$( $USE_SUDO && echo 'sudo docker' || echo 'docker' )"
    SSH_DESTINO=""
else
    DOCKER_DESTINO="ssh $DESTINO $( $USE_SUDO && echo 'sudo docker' || echo 'docker' )"
    SSH_DESTINO="ssh $DESTINO"
fi

# Testar conectividade
$DIALOG --infobox "Testando conectividade...\n\nOrigem:  $ORIGEM\nDestino: $DESTINO" 9 60

testar_conexao() {
    local servidor=$1
    local papel=$2
    local erros=""

    if [ "$servidor" = "localhost" ]; then
        if ! docker info &>/dev/null && ! sudo docker info &>/dev/null; then
            erros="Docker não acessível em $servidor"
        fi
    else
        if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$servidor" exit &>/dev/null; then
            erros="Falha na conexão SSH com $servidor"
        elif ! ssh -o ConnectTimeout=5 "$servidor" "docker info" &>/dev/null && \
             ! ssh -o ConnectTimeout=5 "$servidor" "sudo docker info" &>/dev/null; then
            erros="Docker não acessível em $servidor"
        fi
    fi

    if [ -n "$erros" ]; then
        $DIALOG --title "Erro de Conectividade ($papel)" --msgbox "$erros" 8 60
        exit 1
    fi
}

testar_conexao "$ORIGEM" "Origem"
testar_conexao "$DESTINO" "Destino"

# Carregar volumes
$DIALOG --infobox "Carregando volumes...\n\nOrigem:  $ORIGEM\nDestino: $DESTINO" 9 60

set +e
VOLUMES_ORIGEM=($($DOCKER_ORIGEM volume ls --format "{{.Name}}" 2>/dev/null))
VOLUMES_DESTINO=($($DOCKER_DESTINO volume ls --format "{{.Name}}" 2>/dev/null))
set -e

if [ ${#VOLUMES_ORIGEM[@]} -eq 0 ]; then
    $DIALOG --title "Erro" --msgbox "Nenhum volume encontrado na origem ($ORIGEM)!" 8 60
    exit 1
fi

# Criar mapa de volumes do destino
declare -A destino_volumes
for vol in "${VOLUMES_DESTINO[@]}"; do
    destino_volumes[$vol]=1
done

# Montar checklist (todos pré-selecionados)
VOLUME_LIST=()
for vol in "${VOLUMES_ORIGEM[@]}"; do
    if [ -n "${destino_volumes[$vol]}" ]; then
        status="Existe no destino"
    else
        status="Criar no destino"
    fi
    VOLUME_LIST+=("$vol" "$status" "on")
done

# Seleção de volumes
$DIALOG --title "Selecionar Volumes" \
    --checklist "ESPAÇO para marcar/desmarcar, ENTER para confirmar\n\nOrigem:  $ORIGEM\nDestino: $DESTINO\n\nDesmarque os volumes que NÃO deseja sincronizar." \
    22 72 14 \
    "${VOLUME_LIST[@]}" 2>$TEMPFILE

if [ $? -ne 0 ]; then exit 0; fi

VOLUMES_SELECIONADOS=($(cat $TEMPFILE | tr -d '"'))

if [ ${#VOLUMES_SELECIONADOS[@]} -eq 0 ]; then
    $DIALOG --title "Erro" --msgbox "Nenhum volume selecionado!" 8 60
    exit 1
fi

# Opções de sincronização
$DIALOG --title "Opções de Sincronização" \
    --checklist "Escolha as opções:" 15 60 4 \
    "DRY_RUN" "Simulação (não transferir arquivos)" "$($DRY_RUN && echo on || echo off)" \
    "VERBOSE"  "Mostrar lista de arquivos"            "$($VERBOSE && echo on || echo off)" \
    "USE_SUDO" "Usar sudo para acessar volumes"       "$($USE_SUDO && echo on || echo off)" \
    "DEBUG"    "Apenas mostrar comandos rsync"        "$($DEBUG_MODE && echo on || echo off)" \
    2>$TEMPFILE

OPTIONS=$(cat $TEMPFILE | tr -d '"')
[[ "$OPTIONS" =~ "DRY_RUN"  ]] && DRY_RUN=true  || DRY_RUN=false
[[ "$OPTIONS" =~ "VERBOSE"  ]] && VERBOSE=true   || VERBOSE=false
[[ "$OPTIONS" =~ "USE_SUDO" ]] && USE_SUDO=true  || USE_SUDO=false
[[ "$OPTIONS" =~ "DEBUG"    ]] && DEBUG_MODE=true || DEBUG_MODE=false

# Atualizar comandos Docker conforme USE_SUDO pode ter mudado
if [ "$ORIGEM" = "localhost" ]; then
    DOCKER_ORIGEM="$( $USE_SUDO && echo 'sudo docker' || echo 'docker' )"
else
    DOCKER_ORIGEM="ssh $ORIGEM $( $USE_SUDO && echo 'sudo docker' || echo 'docker' )"
fi
if [ "$DESTINO" = "localhost" ]; then
    DOCKER_DESTINO="$( $USE_SUDO && echo 'sudo docker' || echo 'docker' )"
else
    DOCKER_DESTINO="ssh $DESTINO $( $USE_SUDO && echo 'sudo docker' || echo 'docker' )"
fi

# Resumo e confirmação
MODO="$($DRY_RUN && echo 'DRY-RUN (simulação)' || echo 'EXECUÇÃO REAL')"
VOLS_LISTA=""
for vol in "${VOLUMES_SELECIONADOS[@]}"; do
    VOLS_LISTA+="  • $vol\n"
done

$DIALOG --title "Confirmar Operação" \
    --yesno "Origem:  $ORIGEM\nDestino: $DESTINO\nVolumes: ${#VOLUMES_SELECIONADOS[@]}\nModo:    $MODO\nSudo:    $($USE_SUDO && echo Sim || echo Não)\nDebug:   $($DEBUG_MODE && echo Sim || echo Não)\n\nVolumes selecionados:\n${VOLS_LISTA}\nDeseja continuar?" \
    22 60

if [ $? -ne 0 ]; then exit 0; fi

# Funções de sincronização (mesma lógica do volumes-sync.sh)
get_mountpoint() {
    local servidor=$1
    local docker_cmd=$2
    local volume=$3
    $docker_cmd volume inspect "$volume" --format '{{.Mountpoint}}' 2>/dev/null || echo ""
}

sync_volume() {
    local volume=$1
    local current=$2
    local total=$3

    $DIALOG --infobox "[$current/$total] Volume: $volume\n\nObtendo mountpoints..." 8 60

    # Obter mountpoint da origem
    if [ "$ORIGEM" = "localhost" ]; then
        MOUNT_ORIGEM=$(get_mountpoint "$ORIGEM" "$DOCKER_ORIGEM" "$volume")
    else
        if $USE_SUDO; then
            MOUNT_ORIGEM=$($SSH_ORIGEM "sudo docker volume inspect $volume --format '{{.Mountpoint}}' 2>/dev/null" || echo "")
        else
            MOUNT_ORIGEM=$($SSH_ORIGEM "docker volume inspect $volume --format '{{.Mountpoint}}' 2>/dev/null" || echo "")
        fi
    fi

    if [ -z "$MOUNT_ORIGEM" ]; then
        $DIALOG --title "Erro" --msgbox "[$current/$total] Volume '$volume' não encontrado na origem!" 8 60
        return 1
    fi

    # Obter mountpoint do destino
    if [ "$DESTINO" = "localhost" ]; then
        MOUNT_DESTINO=$(get_mountpoint "$DESTINO" "$DOCKER_DESTINO" "$volume")
    else
        if $USE_SUDO; then
            MOUNT_DESTINO=$($SSH_DESTINO "sudo docker volume inspect $volume --format '{{.Mountpoint}}' 2>/dev/null" || echo "")
        else
            MOUNT_DESTINO=$($SSH_DESTINO "docker volume inspect $volume --format '{{.Mountpoint}}' 2>/dev/null" || echo "")
        fi
    fi

    # Criar volume no destino se não existir
    if [ -z "$MOUNT_DESTINO" ]; then
        $DIALOG --infobox "[$current/$total] Volume: $volume\n\nCriando volume no destino..." 8 60
        if ! $DEBUG_MODE; then
            $DOCKER_DESTINO volume create "$volume" > /dev/null
            if [ "$DESTINO" = "localhost" ]; then
                MOUNT_DESTINO=$(get_mountpoint "$DESTINO" "$DOCKER_DESTINO" "$volume")
            else
                if $USE_SUDO; then
                    MOUNT_DESTINO=$($SSH_DESTINO "sudo docker volume inspect $volume --format '{{.Mountpoint}}' 2>/dev/null")
                else
                    MOUNT_DESTINO=$($SSH_DESTINO "docker volume inspect $volume --format '{{.Mountpoint}}' 2>/dev/null")
                fi
            fi
        fi
    fi

    # Construir opções rsync
    if $VERBOSE; then
        RSYNC_OPTS="-avz --progress -e 'ssh -o StrictHostKeyChecking=no'"
    else
        RSYNC_OPTS="-az --info=progress2 -e 'ssh -o StrictHostKeyChecking=no'"
    fi
    if $DRY_RUN; then
        RSYNC_OPTS="$RSYNC_OPTS --dry-run"
    fi
    if $USE_SUDO; then
        RSYNC_OPTS="$RSYNC_OPTS --rsync-path='sudo rsync'"
    fi

    # Construir comando rsync conforme cenário
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
        # Ambos remotos: executar rsync via SSH na origem
        $USE_SUDO && RSYNC_CMD="ssh $ORIGEM \"sudo rsync $RSYNC_OPTS $MOUNT_ORIGEM/ $DESTINO:$MOUNT_DESTINO/\"" \
                  || RSYNC_CMD="ssh $ORIGEM \"rsync $RSYNC_OPTS $MOUNT_ORIGEM/ $DESTINO:$MOUNT_DESTINO/\""
    fi

    if $DEBUG_MODE; then
        $DIALOG --title "[$current/$total] Comando rsync — $volume" \
            --msgbox "Origem:  $ORIGEM:$MOUNT_ORIGEM\nDestino: $DESTINO:$MOUNT_DESTINO\n\n$RSYNC_CMD" \
            14 72
        return 0
    fi

    $DIALOG --infobox "[$current/$total] Volume: $volume\n\nOrigen:  $ORIGEM:$MOUNT_ORIGEM\nDestino: $DESTINO:$MOUNT_DESTINO\n\n$($DRY_RUN && echo 'Executando DRY-RUN...' || echo 'Sincronizando...')" \
        12 72

    if eval "$RSYNC_CMD" > "$TMPLOG" 2>&1; then
        if $VERBOSE; then
            $DIALOG --title "[$current/$total] $volume — Concluído" \
                --textbox "$TMPLOG" 20 72
        fi
        return 0
    else
        $DIALOG --title "Erro no volume: $volume" \
            --textbox "$TMPLOG" 20 72
        return 1
    fi
}

# Registrar início
START_TIME=$(date +%s)
START_TIME_FORMATTED=$(date '+%d/%m/%Y %H:%M:%S')

# Processar volumes
declare -A RESULTADO_VOLUMES
TOTAL=${#VOLUMES_SELECIONADOS[@]}

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
    else
        RESULTADO_VOLUMES[$volume]="erro"
    fi
done

# Calcular tempo decorrido
END_TIME=$(date +%s)
END_TIME_FORMATTED=$(date '+%d/%m/%Y %H:%M:%S')
ELAPSED=$((END_TIME - START_TIME))
HOURS=$((ELAPSED / 3600))
MINUTES=$(((ELAPSED % 3600) / 60))
SECONDS=$((ELAPSED % 60))
[ $HOURS -gt 0 ]   && ELAPSED_FORMATTED="${HOURS}h ${MINUTES}m ${SECONDS}s" \
|| [ $MINUTES -gt 0 ] && ELAPSED_FORMATTED="${MINUTES}m ${SECONDS}s" \
|| ELAPSED_FORMATTED="${SECONDS}s"

# Resumo final
SUCESSO=0; ERROS=0
RESUMO_VOLS=""
for volume in "${VOLUMES_SELECIONADOS[@]}"; do
    status="${RESULTADO_VOLUMES[$volume]}"
    case "$status" in
        ok)
            $DRY_RUN && RESUMO_VOLS+="  [dry-run] $volume\n" \
                     || { RESUMO_VOLS+="  [✓ ok]    $volume\n"; (( SUCESSO++ )) || true; }
            ;;
        erro)
            RESUMO_VOLS+="  [✗ erro]  $volume\n"
            (( ERROS++ )) || true
            ;;
        debug)
            RESUMO_VOLS+="  [debug]   $volume\n"
            ;;
    esac
done

FINAL_MSG="Início:  $START_TIME_FORMATTED\nTérmino: $END_TIME_FORMATTED\nTempo:   $ELAPSED_FORMATTED\n\n"
if ! $DEBUG_MODE && ! $DRY_RUN; then
    FINAL_MSG+="Sucesso: $SUCESSO  |  Erros: $ERROS  |  Total: $TOTAL\n\n"
fi
FINAL_MSG+="$RESUMO_VOLS"
if $DRY_RUN; then
    FINAL_MSG+="\nUse DRY_RUN=false para executar a sincronização real."
fi
if $DEBUG_MODE; then
    FINAL_MSG+="\nModo debug ativo — apenas comandos foram exibidos."
fi

$DIALOG --title "Concluído" --msgbox "$FINAL_MSG" 24 64
