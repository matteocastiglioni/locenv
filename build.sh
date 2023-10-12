#!/bin/bash

php_version=""
node_version=""
composer_version=""

while getopts "bp:n:c:h" flag
do
    case $flag in
        b)
            # docker build --no-cache -t local:1.0 .
            DOCKER_BUILDKIT=1 docker build --no-cache --target php  $php_version -t php_local:1.0 .
            DOCKER_BUILDKIT=1 docker build --no-cache --target node $node_version -t node_local:1.0 .
            DOCKER_BUILDKIT=1 docker build --no-cache --target composer $composer_version -t composer_local:1.0 .
        ;;
        p) php_version="--build-arg php_version=\"${OPTARG}\"";;
        n) node_version="--build-arg node_version=\"${OPTARG}\"";;
        c) composer_version="--build-arg composer_version=\"${OPTARG}\"";;
        h)
            echo "
Usage: build.sh [OPTIONS]

Options:
    -b      Build images
    -p      PHP version (default 8.1-fpm)
    -n      NodeJS version (default lts)
    -c      Composer version (default lts)
    -h      This help
"
            exit 0
        ;;
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

    printf "#!/bin/sh\n
user=\"-u \$(id -u):\$(id -g) \"\n
for arg in \"\$@\"; do
    case \$arg in
        \"--int\") interactive=\"-it \";;
        \"--root\") user=\"\";;
        *) command=\"\$command \$arg\";;
    esac
done\n
docker run --rm \$interactive\$user-P -v .:\$PWD -w \$PWD -e SHELL=/bin/sh ${image}_local:1.0 %s\$command\n" $command > $executablePath

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
            if ! grep -q 'alias dk="docker compose"' ~/.bashrc; then echo 'alias dk="docker compose"' >> ~/.bashrc; fi

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
        if ! grep -q 'alias dk="docker compose"' ~/.zshrc; then echo 'alias dk="docker compose"' >> ~/.zshrc; fi

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
