#!/bin/bash
#
# curl https://raw.githubusercontent.com/marcelofmatos/scripts/main/docker/volumes-sync.sh | bash
#
# curl https://raw.githubusercontent.com/marcelofmatos/scripts/main/docker/volumes-sync.sh > volumes-sync.sh; bash volumes-sync.sh
#
# Script interativo para sincronizar volumes Docker entre servidores
#
# Variáveis de ambiente disponíveis:
#   ORIGEM      - Servidor de origem (ex: usuario@ip, alias SSH ou 'localhost')
#   DESTINO     - Servidor de destino (ex: usuario@ip, alias SSH ou 'localhost')
#   DRY_RUN     - Simulação sem executar (true/false, padrão: true)
#   VERBOSE     - Mostrar lista de arquivos (true/false, padrão: false)
#   DEBUG       - Apenas mostrar comandos sem executar (true/false, padrão: false)
#   USE_SUDO    - Usar sudo para acessar volumes (true/false, padrão: true)
#
# Exemplos de uso:
#   ORIGEM=usuario@azure DESTINO=usuario@hetzner ./volumes-sync.sh
#   DRY_RUN=false ORIGEM=localhost DESTINO=usuario@hetzner ./volumes-sync.sh
#   DEBUG=true ORIGEM=usuario@azure DESTINO=localhost ./volumes-sync.sh
#   VERBOSE=true DRY_RUN=false ORIGEM=usuario@azure DESTINO=usuario@hetzner ./volumes-sync.sh

set -eo pipefail

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Ler configurações de variáveis de ambiente
# Salvar se DRY_RUN foi definido explicitamente
[ -n "${DRY_RUN+x}" ] && DRY_RUN_ORIGINAL=$DRY_RUN
DRY_RUN=${DRY_RUN:-true}
DEBUG_MODE=${DEBUG:-false}
VERBOSE=${VERBOSE:-false}
ORIGEM=${ORIGEM:-""}
DESTINO=${DESTINO:-""}
USE_SUDO=${USE_SUDO:-true}

# Banner
echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN}  Sincronização de Volumes Docker${NC}"
echo -e "${CYAN}======================================${NC}"
echo ""

# Função para listar servidores disponíveis (SSH config + localhost)
listar_servidores() {
    local titulo=$1
    local SERVIDORES=("localhost")

    # Ler hosts do ~/.ssh/config (excluindo wildcards)
    if [ -f "$HOME/.ssh/config" ]; then
        while IFS= read -r linha; do
            host=$(echo "$linha" | awk '{print $2}')
            [[ "$host" == *"*"* ]] && continue
            [[ "$host" == "localhost" ]] && continue
            SERVIDORES+=("$host")
        done < <(grep -i "^Host " "$HOME/.ssh/config" 2>/dev/null)
    fi

    echo -e "${CYAN}$titulo${NC}" >&2
    echo -e "${BLUE}  0.${NC} (digitar manualmente)" >&2
    for i in "${!SERVIDORES[@]}"; do
        echo -e "${BLUE}  $((i + 1)).${NC} ${SERVIDORES[$i]}" >&2
    done
    echo "" >&2
    echo -e "${YELLOW}Número ou endereço (ex: usuario@ip):${NC}" >&2
    read -r ESCOLHA

    if [[ "$ESCOLHA" =~ ^[0-9]+$ ]]; then
        if [ "$ESCOLHA" -eq 0 ]; then
            echo -e "${YELLOW}Digite o endereço do servidor:${NC}" >&2
            read -r SERVIDOR_ESCOLHIDO
        elif [ "$ESCOLHA" -ge 1 ] && [ "$ESCOLHA" -le "${#SERVIDORES[@]}" ]; then
            SERVIDOR_ESCOLHIDO="${SERVIDORES[$((ESCOLHA - 1))]}"
        else
            echo -e "${RED}✗ Opção inválida!${NC}" >&2
            exit 1
        fi
    else
        SERVIDOR_ESCOLHIDO="$ESCOLHA"
    fi

    echo "$SERVIDOR_ESCOLHIDO"
}

# Solicitar servidores se não fornecidos
if [ -z "$ORIGEM" ]; then
    ORIGEM=$(listar_servidores "Servidores disponíveis - ORIGEM:")
fi

if [ -z "$DESTINO" ]; then
    DESTINO=$(listar_servidores "Servidores disponíveis - DESTINO:")
fi

# Configurar comandos Docker
if [ "$ORIGEM" = "localhost" ]; then
    if $USE_SUDO; then
        DOCKER_ORIGEM="sudo docker"
    else
        DOCKER_ORIGEM="docker"
    fi
    SSH_ORIGEM=""
else
    if $USE_SUDO; then
        DOCKER_ORIGEM="ssh $ORIGEM sudo docker"
    else
        DOCKER_ORIGEM="ssh $ORIGEM docker"
    fi
    SSH_ORIGEM="ssh $ORIGEM"
fi

if [ "$DESTINO" = "localhost" ]; then
    if $USE_SUDO; then
        DOCKER_DESTINO="sudo docker"
    else
        DOCKER_DESTINO="docker"
    fi
    SSH_DESTINO=""
else
    if $USE_SUDO; then
        DOCKER_DESTINO="ssh $DESTINO sudo docker"
    else
        DOCKER_DESTINO="ssh $DESTINO docker"
    fi
    SSH_DESTINO="ssh $DESTINO"
fi

# Função para testar conectividade com servidor
testar_conexao() {
    local servidor=$1
    local papel=$2

    if [ "$servidor" = "localhost" ]; then
        if docker info &>/dev/null || sudo docker info &>/dev/null; then
            echo -e "${GREEN}✓ $papel ($servidor): Docker acessível${NC}"
            return 0
        else
            echo -e "${RED}✗ $papel ($servidor): Docker não acessível${NC}"
            return 1
        fi
    else
        echo -ne "${CYAN}  Testando SSH $papel ($servidor)...${NC} "
        SSH_ERR=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$servidor" exit 2>&1)
        if [ $? -ne 0 ]; then
            echo -e "${RED}✗ Falha na conexão SSH!${NC}"
            echo -e "${RED}  $SSH_ERR${NC}"
            return 1
        fi
        echo -ne "${GREEN}✓ SSH OK${NC} | "
        if ssh -o ConnectTimeout=5 "$servidor" "docker info" &>/dev/null || \
           ssh -o ConnectTimeout=5 "$servidor" "sudo docker info" &>/dev/null; then
            echo -e "${GREEN}Docker acessível${NC}"
            return 0
        else
            echo -e "${RED}✗ Docker não acessível${NC}"
            return 1
        fi
    fi
}

echo ""
echo -e "${CYAN}Testando conectividade...${NC}"
testar_conexao "$ORIGEM" "Origem" || exit 1
testar_conexao "$DESTINO" "Destino" || exit 1

echo ""
echo -e "${GREEN}✓ Origem:${NC} $ORIGEM"
echo -e "${GREEN}✓ Destino:${NC} $DESTINO"
if $DRY_RUN; then
    echo -e "${YELLOW}⚠ Modo:${NC} DRY-RUN (use DRY_RUN=false para executar)"
else
    echo -e "${RED}⚠ Modo:${NC} EXECUÇÃO REAL"
fi
if $DEBUG_MODE; then
    echo -e "${CYAN}⚠ Debug:${NC} Apenas mostrar comandos"
fi
echo ""

# Listar volumes de ambos os servidores
echo -e "${CYAN}Carregando volumes...${NC}"
set +e
VOLUMES_ORIGEM=($($DOCKER_ORIGEM volume ls --format "{{.Name}}" 2>/dev/null))
VOLUMES_DESTINO=($($DOCKER_DESTINO volume ls --format "{{.Name}}" 2>/dev/null))
set -e

if [ ${#VOLUMES_ORIGEM[@]} -eq 0 ]; then
    echo -e "${RED}✗ Nenhum volume encontrado na origem!${NC}"
    exit 1
fi

echo ""
echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN}  Volumes Disponíveis${NC}"
echo -e "${CYAN}======================================${NC}"
echo ""

# Cabeçalho das colunas
printf "${BLUE}%-4s %-35s %-35s${NC}\n" "#" "ORIGEM ($ORIGEM)" "DESTINO ($DESTINO)"
printf "${BLUE}%-4s %-35s %-35s${NC}\n" "----" "-----------------------------------" "-----------------------------------"

# Criar array associativo para volumes do destino
declare -A destino_volumes
for vol in "${VOLUMES_DESTINO[@]}"; do
    destino_volumes[$vol]=1
done

# Listar volumes em colunas
for i in "${!VOLUMES_ORIGEM[@]}"; do
    vol_origem="${VOLUMES_ORIGEM[$i]}"
    num=$((i + 1))
    
    # Verificar se existe no destino
    if [ -n "${destino_volumes[$vol_origem]}" ]; then
        vol_destino="${GREEN}✓${NC} $vol_origem"
    else
        vol_destino="${YELLOW}✗${NC} (não existe)"
    fi
    
    printf "${CYAN}%-4s${NC} %-35s %-35s\n" "$num." "$vol_origem" "$(echo -e $vol_destino)"
done

echo ""

# Solicitar seleção
echo -e "${BLUE}Digite os números dos volumes para sincronizar (ex: 1 3 5 ou 'all'):${NC}"
read -r SELECAO

# Processar seleção
if [ "$SELECAO" = "all" ]; then
    VOLUMES_SELECIONADOS=("${VOLUMES_ORIGEM[@]}")
else
    VOLUMES_SELECIONADOS=()
    for num in $SELECAO; do
        idx=$((num - 1))
        if [ $idx -ge 0 ] && [ $idx -lt ${#VOLUMES_ORIGEM[@]} ]; then
            VOLUMES_SELECIONADOS+=("${VOLUMES_ORIGEM[$idx]}")
        else
            echo -e "${YELLOW}⚠ Índice $num ignorado (fora do intervalo)${NC}"
        fi
    done
fi

if [ ${#VOLUMES_SELECIONADOS[@]} -eq 0 ]; then
    echo -e "${RED}✗ Nenhum volume selecionado!${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Volumes selecionados:${NC}"
printf '%s\n' "${VOLUMES_SELECIONADOS[@]}" | nl -w2 -s'. '
echo ""

# Perguntar se deve desativar DRY_RUN
if $DRY_RUN && [ -z "${DRY_RUN_ORIGINAL+x}" ]; then
    echo -e "${YELLOW}Deseja desativar o modo DRY_RUN e executar a sincronização real? (s/N):${NC}"
    read -r DESATIVAR_DRY_RUN
    if [[ "$DESATIVAR_DRY_RUN" =~ ^[Ss]$ ]]; then
        DRY_RUN=false
        echo -e "${RED}✓ Modo DRY_RUN desativado - execução real será realizada${NC}"
    else
        echo -e "${YELLOW}✓ Modo DRY_RUN mantido - apenas simulação${NC}"
    fi
    echo ""
fi

# Mostrar resumo
echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN}  Resumo da Operação${NC}"
echo -e "${CYAN}======================================${NC}"
echo -e "${BLUE}Origem:${NC}    $ORIGEM"
echo -e "${BLUE}Destino:${NC}   $DESTINO"
echo -e "${BLUE}Volumes:${NC}   ${#VOLUMES_SELECIONADOS[@]}"
if $DRY_RUN; then
    echo -e "${BLUE}Modo:${NC}      ${YELLOW}DRY-RUN (simulação)${NC}"
else
    echo -e "${BLUE}Modo:${NC}      ${RED}EXECUÇÃO REAL${NC}"
fi
if $USE_SUDO; then
    echo -e "${BLUE}Permissões:${NC} Com sudo"
else
    echo -e "${BLUE}Permissões:${NC} Sem sudo"
fi
echo -e "${CYAN}======================================${NC}"
echo ""

# Confirmar
if ! $DEBUG_MODE; then
    echo -e "${YELLOW}Deseja continuar? (s/N):${NC}"
    read -r CONFIRMAR
    if [[ ! "$CONFIRMAR" =~ ^[Ss]$ ]]; then
        echo "Cancelado."
        exit 0
    fi
    echo ""
fi

# Função para obter mountpoint
get_mountpoint() {
    local servidor=$1
    local docker_cmd=$2
    local volume=$3
    
    $docker_cmd volume inspect "$volume" --format '{{.Mountpoint}}' 2>/dev/null || echo ""
}

# Função para executar ou mostrar rsync
sync_volume() {
    local volume=$1
    
    echo -e "${CYAN}─────────────────────────────────────${NC}"
    echo -e "${CYAN}Volume: $volume${NC}"
    echo -e "${CYAN}─────────────────────────────────────${NC}"
    
    # Obter mountpoints
    if [ "$ORIGEM" = "localhost" ]; then
        MOUNT_ORIGEM=$(get_mountpoint "$ORIGEM" "$DOCKER_ORIGEM" "$volume")
    else
        if $USE_SUDO; then
            MOUNT_ORIGEM=$($SSH_ORIGEM "sudo docker volume inspect $volume --format '{{.Mountpoint}}' 2>/dev/null" || echo "")
        else
            MOUNT_ORIGEM=$($SSH_ORIGEM "docker volume inspect $volume --format '{{.Mountpoint}}' 2>/dev/null" || echo "")
        fi
    fi
    
    if [ "$DESTINO" = "localhost" ]; then
        MOUNT_DESTINO=$(get_mountpoint "$DESTINO" "$DOCKER_DESTINO" "$volume")
    else
        if $USE_SUDO; then
            MOUNT_DESTINO=$($SSH_DESTINO "sudo docker volume inspect $volume --format '{{.Mountpoint}}' 2>/dev/null" || echo "")
        else
            MOUNT_DESTINO=$($SSH_DESTINO "docker volume inspect $volume --format '{{.Mountpoint}}' 2>/dev/null" || echo "")
        fi
    fi
    
    if [ -z "$MOUNT_ORIGEM" ]; then
        echo -e "${RED}✗ Volume não encontrado na origem!${NC}"
        return 1
    fi
    
    # Verificar/criar volume no destino
    if [ -z "$MOUNT_DESTINO" ]; then
        echo -e "${YELLOW}⚠ Volume não existe no destino. Criando...${NC}"
        if $DEBUG_MODE; then
            if [ "$DESTINO" = "localhost" ]; then
                if $USE_SUDO; then
                    echo "sudo docker volume create $volume"
                else
                    echo "docker volume create $volume"
                fi
            else
                if $USE_SUDO; then
                    echo "ssh $DESTINO sudo docker volume create $volume"
                else
                    echo "ssh $DESTINO docker volume create $volume"
                fi
            fi
        else
            $DOCKER_DESTINO volume create "$volume" > /dev/null
            echo -e "${GREEN}✓ Volume criado no destino${NC}"
            
            # Obter mountpoint novamente
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
    
    # Construir comando rsync
    if $VERBOSE; then
        # Modo verbose: listar todos os arquivos
        RSYNC_OPTS="-avz --progress -e 'ssh -o StrictHostKeyChecking=no'"
    else
        # Modo normal: apenas barra de progresso
        RSYNC_OPTS="-az --info=progress2 -e 'ssh -o StrictHostKeyChecking=no'"
    fi
    
    if $DRY_RUN; then
        RSYNC_OPTS="$RSYNC_OPTS --dry-run"
    fi
    
    # Adicionar --rsync-path se necessário
    if $USE_SUDO; then
        RSYNC_OPTS="$RSYNC_OPTS --rsync-path='sudo rsync'"
    fi
    
    # Montar comando baseado em origem/destino local ou remoto
    if [ "$ORIGEM" = "localhost" ] && [ "$DESTINO" = "localhost" ]; then
        if $USE_SUDO; then
            RSYNC_CMD="sudo rsync $RSYNC_OPTS $MOUNT_ORIGEM/ $MOUNT_DESTINO/"
        else
            RSYNC_CMD="rsync $RSYNC_OPTS $MOUNT_ORIGEM/ $MOUNT_DESTINO/"
        fi
    elif [ "$ORIGEM" = "localhost" ]; then
        if $USE_SUDO; then
            RSYNC_CMD="sudo rsync $RSYNC_OPTS $MOUNT_ORIGEM/ $DESTINO:$MOUNT_DESTINO/"
        else
            RSYNC_CMD="rsync $RSYNC_OPTS $MOUNT_ORIGEM/ $DESTINO:$MOUNT_DESTINO/"
        fi
    elif [ "$DESTINO" = "localhost" ]; then
        if $USE_SUDO; then
            RSYNC_CMD="sudo rsync $RSYNC_OPTS $ORIGEM:$MOUNT_ORIGEM/ $MOUNT_DESTINO/"
        else
            RSYNC_CMD="rsync $RSYNC_OPTS $ORIGEM:$MOUNT_ORIGEM/ $MOUNT_DESTINO/"
        fi
    else
        # Ambos remotos - rsync via SSH com sudo tanto na origem quanto no destino
        if $USE_SUDO; then
            RSYNC_CMD="ssh $ORIGEM \"sudo rsync $RSYNC_OPTS $MOUNT_ORIGEM/ $DESTINO:$MOUNT_DESTINO/\""
        else
            RSYNC_CMD="ssh $ORIGEM \"rsync $RSYNC_OPTS $MOUNT_ORIGEM/ $DESTINO:$MOUNT_DESTINO/\""
        fi
    fi
    
    echo ""
    echo -e "${BLUE}Origem:${NC}  $ORIGEM:$MOUNT_ORIGEM"
    echo -e "${BLUE}Destino:${NC} $DESTINO:$MOUNT_DESTINO"
    echo ""
    
    if $DEBUG_MODE; then
        echo -e "${YELLOW}Comando rsync:${NC}"
        echo "$RSYNC_CMD"
        echo ""
    else
        if $DRY_RUN; then
            echo -e "${YELLOW}Executando DRY-RUN...${NC}"
        else
            echo -e "${GREEN}Sincronizando...${NC}"
        fi
        echo ""
        
        # Executar rsync
        if ! eval "$RSYNC_CMD"; then
            echo ""
            echo -e "${RED}✗ Erro ao executar rsync!${NC}"
            echo -e "${YELLOW}Comando executado:${NC}"
            echo "$RSYNC_CMD"
            echo ""
            return 1
        fi
        
        echo ""
        if $DRY_RUN; then
            echo -e "${YELLOW}✓ DRY-RUN completo (nenhum arquivo foi transferido)${NC}"
        else
            echo -e "${GREEN}✓ Sincronização completa!${NC}"
        fi
    fi
    
    echo ""
}

# Processar cada volume selecionado, sem parar no erro
declare -A RESULTADO_VOLUMES
TOTAL=${#VOLUMES_SELECIONADOS[@]}

for i in "${!VOLUMES_SELECIONADOS[@]}"; do
    volume="${VOLUMES_SELECIONADOS[$i]}"
    echo -e "${CYAN}[$(( i + 1 ))/$TOTAL]${NC}"
    if $DEBUG_MODE; then
        sync_volume "$volume"
        RESULTADO_VOLUMES[$volume]="debug"
    else
        set +e
        sync_volume "$volume"
        STATUS=$?
        set -e
        if [ $STATUS -eq 0 ]; then
            RESULTADO_VOLUMES[$volume]="ok"
        else
            RESULTADO_VOLUMES[$volume]="erro"
        fi
    fi
done

# Resumo final por volume
echo ""
echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN}  Resumo por Volume${NC}"
echo -e "${CYAN}======================================${NC}"
printf "${BLUE}%-40s %-10s${NC}\n" "Volume" "Status"
printf "${BLUE}%-40s %-10s${NC}\n" "----------------------------------------" "----------"

SUCESSO=0
ERROS=0
for volume in "${VOLUMES_SELECIONADOS[@]}"; do
    status="${RESULTADO_VOLUMES[$volume]}"
    case "$status" in
        ok)
            if $DRY_RUN; then
                printf "%-40s ${YELLOW}%-10s${NC}\n" "$volume" "dry-run"
            else
                printf "%-40s ${GREEN}%-10s${NC}\n" "$volume" "✓ ok"
                (( SUCESSO++ )) || true
            fi
            ;;
        erro)
            printf "%-40s ${RED}%-10s${NC}\n" "$volume" "✗ erro"
            (( ERROS++ )) || true
            ;;
        debug)
            printf "%-40s ${CYAN}%-10s${NC}\n" "$volume" "debug"
            ;;
    esac
done

echo ""
if ! $DEBUG_MODE && ! $DRY_RUN; then
    echo -e "Sucesso: ${GREEN}$SUCESSO${NC}  |  Erros: ${RED}$ERROS${NC}  |  Total: $TOTAL"
fi
if $DRY_RUN; then
    echo -e "${YELLOW}Use DRY_RUN=false para executar a sincronização real${NC}"
fi
if $DEBUG_MODE; then
    echo -e "${CYAN}Modo debug ativo - apenas comandos foram mostrados${NC}"
fi
echo ""
