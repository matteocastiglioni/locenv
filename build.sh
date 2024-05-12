#!/bin/bash

php_version=""
node_version=""
composer_version=""
docker_config_file="$HOME/.docker/config.json"

help() {
    echo "
Usage: bash build.sh [OPTIONS]

Options:
    -b      Build images
    -p      PHP version (default 8.1-alpine)
    -n      NodeJS version (default lts-alpine)
    -c      Composer version (default lts)
    -h      This help
"
    exit 0
}

# checks if the shell is bash and if at least one argument is present
if [ ! -z "$(type -p)" -o "$#" = 0 ]; then help; fi

while getopts ":bp:n:c:h" flag
do
    case $flag in
        b)
            if [ ! -f $docker_config_file ]
            then
                case $(uname | tr '[:upper:]' '[:lower:]') in
                    linux*)
                        creds_store="wincred.exe"
                    ;;
                    darwin*) # OSX
                        creds_store="osxkeychain"
                    ;;
                    *)
                        echo "Unknown OS"
                        exit 1
                    ;;
                esac

                printf "{
    \"auths\": {
        \"https://index.docker.io/v1/\": {}
    },
    \"credsStore\": \"$creds_store\"
}
" > $docker_config_file

                chown $SUDO_USER:$SUDO_USER $docker_config_file
            else
                if ! grep -q 'credsStore' $docker_config_file || ! grep -q 'auths' $docker_config_file
                then
                    echo "Missing \"auths\" or \"credsStore\" on $docker_config_file"
                    exit 1
                fi
            fi

            # docker build --no-cache -t local:1.0 .
            DOCKER_BUILDKIT=1 docker build --no-cache --target php  $php_version -t php_local:1.0 .
            DOCKER_BUILDKIT=1 docker build --no-cache --target node $node_version -t node_local:1.0 .
            DOCKER_BUILDKIT=1 docker build --no-cache --target composer $composer_version -t composer_local:1.0 .
        ;;
        p) php_version="--build-arg php_version=\"${OPTARG}\"" ;;
        n) node_version="--build-arg node_version=\"${OPTARG}\"" ;;
        c) composer_version="--build-arg composer_version=\"${OPTARG}\"" ;;
        h|*) help ;;
    esac
done

binPath=.bin
mkdir -p $binPath
chown $SUDO_USER:$SUDO_USER $binPath

commands=("composer" "php" "node" "npm" "npx")

for command in "${commands[@]}"
do
    executablePath=./$binPath/$command

    if [ ${command} = "npm" -o ${command} = "npx" ]; then image="node"; else image="$command"; fi

    printf "#!/bin/sh

# detect if in interactive shell
[ -t 0 ] && interactive=\"-it \"

user=\"-u \$(id -u):\$(id -g) \"

while [ \$# -gt 0 ]
do
    case \$1 in
        -i|--int) interactive=\"-it \" ;;
        -r|--root) user=\"\" ;;
        -p|--port)
            port=\"-p \$2:\$2 \"
            shift
            ;;
        *) args=\"\$args \$1\" ;;
    esac

    shift
done

docker run --rm \$interactive\$user\$port-P -v .:\$PWD -w \$PWD -e SHELL=/bin/sh ${image}_local:1.0 %s\$args
" $command > $executablePath

    chmod +x $executablePath
    chown $SUDO_USER:$SUDO_USER $executablePath
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
