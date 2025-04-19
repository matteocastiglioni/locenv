#!/bin/bash

# Definizione degli script wrapper
STANDARD_WRAPPER='#!/bin/sh

user="-u $(id -u):$(id -g)"
interactive=""
command=""

for arg in "$@"; do
    case $arg in
        "--int") interactive="-it";;
        "--root") user="";;
        *) command="$command $arg";;
    esac
done

docker run --rm $interactive $user -P \
    -v .:$PWD \
    -w $PWD \
    -e SHELL=/bin/sh \
    %s_local:1.0 \
    %s $command'

OLLAMA_WRAPPER='#!/bin/sh

if ! command -v nvidia-ctk >/dev/null 2>&1; then
    echo "nvidia-ctk command not found. Installing NVIDIA Container Toolkit ..."

    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed "s#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g" \
    | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

    sudo apt-get update
    sudo apt-get install -y nvidia-container-toolkit
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo systemctl restart docker
fi

# Show help if no command is provided
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

if [ "$1" = "serve" ]; then
    if ! docker ps -q -f name=ollama | grep -q .; then
        docker run -d --gpus=all -v ollama:/root/.ollama -p 11434:11434 --name ollama ollama/ollama
    else
        echo "Ollama service is already running."
    fi
    
    exit 0
fi

docker exec -it ollama ollama "$@"'

# Definisci un array associativo per tutti i comandi e le loro configurazioni
declare -A commands=(
    ["php"]="version=8-alpine;build=true"
    ["node"]="version=lts-alpine;build=true"
    ["npm"]="version=lts-alpine;build=false;use=node"
    ["npx"]="version=lts-alpine;build=false;use=node"
    ["composer"]="version=lts;build=true"
    ["git"]="version=2.47.2;build=true"
    ["python"]="version=3-alpine;build=true"
    ["ollama"]="version=;build=false"
)

binPath=.bin
mkdir -p $binPath
chown $SUDO_USER:$SUDO_USER $binPath

# Build docker images e genera gli script wrapper
for command in "${!commands[@]}"
do
    # Parse command settings
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

    # Build docker image se necessario
    if [ "$build" = "true" ]; then
        docker build --no-cache \
            --target "$command" \
            --build-arg VERSION="$version" \
            -t "${command}_local:1.0" .
    fi

    # Genera script wrapper
    executablePath=./$binPath/$command

    # Determina quale immagine usare
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
        printf "$STANDARD_WRAPPER" "$image" "$image" > "$executablePath"
    fi

    chmod +x "$executablePath"
    chown "$SUDO_USER:$SUDO_USER" "$executablePath"
done

case $(uname | tr '[:upper:]' '[:lower:]') in
	linux*)
		if [[ $(lsb_release -d | awk -F"\t" '{print $2}' | awk -F " " '{print $1}' | tr '[:upper:]' '[:lower:]') == 'ubuntu' ]]
        then
            LOCAL_BIN_PATH=$PWD/$binPath

            if ! grep -q "export PATH=\$PATH:$LOCAL_BIN_PATH" ~/.bashrc
            then
                OLD_IFS=$IFS
                IFS=":"
                FOUND=false

                for path in $PATH; do
                    if [[ $path == $LOCAL_BIN_PATH ]]; then FOUND=true; fi
                done

                IFS=$OLD_IFS

                if [[ $FOUND == false ]]; then echo "export PATH=\$PATH:$LOCAL_BIN_PATH" >> ~/.bashrc; fi
            fi

            if ! grep -q 'alias dk="docker"' ~/.bashrc; then echo 'alias dk="docker"' >> ~/.bashrc; fi
            if ! grep -q 'alias dkc="docker compose"' ~/.bashrc; then echo 'alias dkc="docker compose"' >> ~/.bashrc; fi

            exec bash # reload bash
        fi
    ;;
    darwin*) # OSX
        LOCAL_BIN_PATH=$PWD/$binPath

        if ! grep -q "export PATH=\$PATH:$LOCAL_BIN_PATH" ~/.zshrc
        then
            OLD_IFS=$IFS
            IFS=":"
            FOUND=false

            for path in $PATH; do
                if [[ $path == $LOCAL_BIN_PATH ]]; then FOUND=true; fi
            done

            IFS=$OLD_IFS

            if [[ $FOUND == false ]]; then echo "export PATH=\$PATH:$LOCAL_BIN_PATH" >> ~/.zshrc; fi
        fi

        if ! grep -q 'alias dk="docker"' ~/.zshrc; then echo 'alias dk="docker"' >> ~/.zshrc; fi
        if ! grep -q 'alias dkc="docker compose"' ~/.zshrc; then echo 'alias dkc="docker compose"' >> ~/.zshrc; fi

        exec zsh # reload zsh
    ;;
    *)
        echo "Unknown OS"
        exit 1
    ;;
esac

# sed -i '/alias dk="docker"/d' ~/.bashrc # remove dk alias
# sed -i '/alias dkc="docker compose"/d' ~/.bashrc # remove dkc alias

exit 0
