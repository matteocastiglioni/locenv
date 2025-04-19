#!/bin/bash

STANDARD_WRAPPER='#!/bin/sh

# detect if in interactive shell
[ -t 0 ] && interactive="-it"

user="-u $(id -u):$(id -g)"

while [ $# -gt 0 ]
do
    case $1 in
        --int) interactive="-it";;
        --root) user="";;
        --port)
            port="-p $2:$2"
            shift
            ;;
        *) args="$args $1";;
    esac

    shift
done

docker run --rm $interactive $user $port -P \
    -v .:$PWD \
    -w $PWD \
    -e SHELL=/bin/sh \
    %s_local:1.0 \
    %s $args'

OLLAMA_WRAPPER='#!/bin/sh

if [ $# -eq 0 ]; then
    echo "Usage: ollama COMMAND"
    echo ""
    echo "Commands:"
    echo "  serve       Start ollama"
    echo "  create      Create a model from a Modelfile"
    echo "  show        Show information for a model"
    echo "  run         Run a model"
    echo "  stop        Stop a running model"
    echo "  pull        Pull a model from a registry"
    echo "  push        Push a model to a registry"
    echo "  list        List models"
    echo "  ps          List running models"
    echo "  cp          Copy a model"
    echo "  rm          Remove a model"
    echo "  help        Help about any command"

    exit 0
fi

start_ollama_service() {
    GPU_FLAG=""
    if command -v nvidia-smi > /dev/null 2>&1; then
        GPU_FLAG="--gpus=all"
    fi
    docker run -d $GPU_FLAG -v ollama:/root/.ollama -p 11434:11434 --name ollama ollama/ollama
}

is_ollama_running() {
    docker ps -q -f name=ollama | grep -q .
}

execute_ollama_command() {
    docker exec -it ollama ollama "$@"
}

start_and_execute() {
    echo "Ollama service is not running"
    read -r -p "Do you want to start the service? (y/n) " answer
    if [ "$answer" = "y" ]; then
        start_ollama_service
        execute_ollama_command "$@"
    fi
}

case "$1" in
    "serve")
        if is_ollama_running; then
            echo "Ollama service is already running"
            exit 0
        fi
        
        start_ollama_service
        ;;
    *)
        if is_ollama_running; then
            execute_ollama_command "$@"
        else
            start_and_execute "$@"
        fi
        ;;
esac'

declare -A commands=(
    ["php"]="version=8-alpine;build=true"
    ["node"]="version=lts-alpine;build=true"
    ["npm"]="version=lts-alpine;build=false;use=node"
    ["npx"]="version=lts-alpine;build=false;use=node"
    ["composer"]="version=lts;build=true"
    ["git"]="version=2.47.2;build=true"
    ["python"]="version=3.12-slim;build=true"
    ["pip"]="version=3.12-slim;build=false;use=python"
    ["ollama"]="version=;build=false"
)

binPath=.bin
mkdir -p $binPath
chown $SUDO_USER:$SUDO_USER $binPath

for command in "${!commands[@]}"
do
    IFS=';' read -r -a settings <<< "${commands[$command]}"
    build="false"
    version=""
    use=""
    
    for setting in "${settings[@]}"
    do
        key="${setting%%=*}"
        value="${setting#*=}"
        case "$key" in
            "version") version="$value" ;;
            "build") build="$value" ;;
            "use") use="$value" ;;
        esac
    done

    if [ "$build" = "true" ]; then
        docker build --no-cache \
            --target "$command" \
            --build-arg VERSION="$version" \
            -t "${command}_local:1.0" .
    fi

    executablePath=./$binPath/$command

    if [ -n "$use" ]; then
        image="$use"
    else
        image="$command"
    fi

    if [ "$command" = "ollama" ]; then
        printf "%s" "$OLLAMA_WRAPPER" > "$executablePath"
    elif [ "$command" = "git" ]; then
        printf "$STANDARD_WRAPPER" "$image" "" > "$executablePath"
    else
        printf "$STANDARD_WRAPPER" "$image" "$command" > "$executablePath"
    fi

    chmod +x "$executablePath"
    chown "$SUDO_USER:$SUDO_USER" "$executablePath"
done

# Determine shell config file and shell based on OS
case $(uname -s | tr '[:upper:]' '[:lower:]') in
    linux*)
        [ "$(lsb_release -si | tr '[:upper:]' '[:lower:]')" != "ubuntu" ] && exit 0
        SHELL_RC=~/.bashrc
        SHELL_CMD=bash
        ;;
    darwin*)
        SHELL_RC=~/.zshrc
        SHELL_CMD=zsh
        ;;
    *)
        echo "Unknown OS"
        exit 1
        ;;
esac

LOCAL_BIN_PATH=$PWD/$binPath

# Check if path already exists in PATH
if ! echo $PATH | tr ':' '\n' | grep -Fxq "$LOCAL_BIN_PATH"; then
    echo "export PATH=\$PATH:$LOCAL_BIN_PATH" >> "$SHELL_RC"
fi

# Add docker aliases if not present
for alias in 'dk="docker"' 'dkc="docker compose"'; do
    grep -q "alias $alias" "$SHELL_RC" || echo "alias $alias" >> "$SHELL_RC"
done

# Reload shell
exec $SHELL_CMD

# sed -i '/alias dk="docker"/d' ~/.bashrc # remove dk alias
# sed -i '/alias dkc="docker compose"/d' ~/.bashrc # remove dkc alias
