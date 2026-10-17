#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${HOME:-}" ]]; then
    printf '%s\n' 'Error: HOME is not set.' >&2
    exit 1
fi

BIN_PATH="$HOME/.local/bin"
ENV_FILE="$SCRIPT_DIR/.env"

PHP_VERSION="${PHP_VERSION:-8.4-alpine}"
NODE_VERSION="${NODE_VERSION:-22-alpine}"
COMPOSER_VERSION="${COMPOSER_VERSION:-2}"
IMAGE_TAG="${IMAGE_TAG:-1.0}"

FORCE=false
NO_CACHE=false

usage() {
    cat <<'EOF'
Usage: ./build.sh [OPTIONS]

Build the Docker images and install the command shims.

Options:
  --force       Overwrite existing dispatcher and shims without prompting.
  --no-cache    Build images without using the Docker build cache.
  -h, --help    Show this help.
EOF
}

for argument in "$@"; do
    case "$argument" in
        --force)
            FORCE=true
            ;;
        --no-cache)
            NO_CACHE=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Error: unknown option: %s\n\n' "$argument" >&2
            usage >&2
            exit 2
            ;;
    esac
done

read_env_value() {
    local key="$1"
    local line name value

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"

        if [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi

        if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=(.*)$ ]]; then
            name="${BASH_REMATCH[1]}"
            [[ "$name" == "$key" ]] || continue

            value="${BASH_REMATCH[2]}"
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"

            case "$value" in
                \"*\")
                    value="${value#\"}"
                    value="${value%\"}"
                    ;;
                \'*\')
                    value="${value#\'}"
                    value="${value%\'}"
                    ;;
            esac

            printf '%s\n' "$value"
            return 0
        fi
    done < "$ENV_FILE"

    return 1
}

if [[ -f "$ENV_FILE" ]]; then
    for variable in PHP_VERSION NODE_VERSION COMPOSER_VERSION IMAGE_TAG; do
        if value="$(read_env_value "$variable")"; then
            printf -v "$variable" '%s' "$value"
        fi
    done
fi

for variable in PHP_VERSION NODE_VERSION COMPOSER_VERSION IMAGE_TAG; do
    value="${!variable}"
    if [[ -z "$value" || ! "$value" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        printf 'Error: %s must be a simple Docker tag without whitespace or shell metacharacters.\n' "$variable" >&2
        exit 1
    fi
done

if ! command -v docker >/dev/null 2>&1; then
    printf '%s\n' 'Error: Docker is not installed or is not available in PATH.' >&2
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    printf '%s\n' 'Error: the Docker daemon is not available.' >&2
    exit 1
fi

mkdir -p "$BIN_PATH"

should_install_file() {
    local path="$1"
    local answer

    if [[ -L "$path" ]]; then
        printf 'Refusing to overwrite symlink: %s\n' "$path" >&2
        return 1
    fi

    if [[ "$FORCE" == true ]]; then
        return 0
    fi

    if [[ -e "$path" ]]; then
        if [[ ! -t 0 ]]; then
            printf 'Skipping existing file: %s\n' "$path" >&2
            return 1
        fi

        read -r -p "File $path already exists. Overwrite it? (y/n) " answer
        case "$answer" in
            y|Y)
                return 0
                ;;
            *)
                return 1
                ;;
        esac
    fi

    return 0
}

commands=(php node npm npx composer)
selected_files=()

for file in "${commands[@]}"; do
    if should_install_file "$BIN_PATH/$file"; then
        selected_files+=("$file")
    fi
done

if [[ -e "$BIN_PATH/locenv" && ! -L "$BIN_PATH/locenv" ]]; then
    rm -f "$BIN_PATH/locenv"
fi

if [[ "${#selected_files[@]}" -eq 0 ]]; then
    printf '%s\n' 'No shims selected; nothing to do.'
    exit 0
fi

build_target() {
    local target="$1"
    local image="${target}_local:${IMAGE_TAG}"
    local build_options=(--pull)

    if [[ "$NO_CACHE" == true ]]; then
        build_options+=(--no-cache)
    fi

    printf 'Building %s...\n' "$image"
    docker build "${build_options[@]}" \
        --target "$target" \
        --build-arg "PHP_VERSION=$PHP_VERSION" \
        --build-arg "NODE_VERSION=$NODE_VERSION" \
        --build-arg "COMPOSER_VERSION=$COMPOSER_VERSION" \
        -t "$image" \
        "$SCRIPT_DIR"
}

build_target php
build_target node
build_target composer

DISPATCHER=$(cat <<'DISPATCHER'
#!/usr/bin/env bash

set -Eeuo pipefail

SELF_NAME="${0##*/}"

error() {
    printf 'locenv: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage:
    COMMAND [WRAPPER_OPTIONS] [COMMAND_OPTIONS]

Commands:
  php       Run PHP in Docker
  node      Run Node.js in Docker
  npm       Run npm in Docker
  npx       Run npx in Docker
  composer  Run Composer in Docker

Wrapper options:
  --locenv-root, --ler              Run as root inside the container
  --locenv-port PORT                Publish the same host/container port
  --locenv-port HOST:CONTAINER      Publish different host/container ports
    --locenv-help, --leh              Show this shim help

Wrapper options are accepted only immediately after the shim command. Once a
command argument is found, all remaining arguments are passed to COMMAND.
EOF
}

case "$SELF_NAME" in
    .locenv-dispatcher)
        [[ $# -gt 0 ]] || error 'internal dispatcher requires a shim command.'
        command_name="$1"
        shift
        ;;
    php|node|npm|npx|composer)
        command_name="$SELF_NAME"
        ;;
    *)
        error "unknown shim name: $SELF_NAME"
        ;;
esac

command_args=()
wrapper_options=()
publish_requested=false

while (( $# > 0 )); do
    if [[ "$1" == '--' ]]; then
        shift
        command_args+=("$@")
        break
    fi

    case "$1" in
        --locenv-root|--ler)
            wrapper_options+=(--locenv-root)
            ;;
        --locenv-port|--lep)
            [[ $# -ge 2 ]] || error '--locenv-port requires a value.'
            wrapper_options+=(--locenv-port "$2")
            publish_requested=true
            shift
            ;;
        --locenv-port=*|--lep=*)
            wrapper_options+=(--locenv-port "${1#*=}")
            publish_requested=true
            ;;
        --locenv-help|--leh)
            usage
            exit 0
            ;;
        *)
            command_args+=("$@")
            break
            ;;
    esac

    shift
done

case "$command_name" in
    php|node|npm|npx|composer)
        ;;
    *)
        error "unsupported shim command: $command_name"
        ;;
esac

case "$command_name" in
    php)
        image="php_local:__IMAGE_TAG__"
        image_command='php'
        cache_name=''
        ;;
    node)
        image="node_local:__IMAGE_TAG__"
        image_command='node'
        cache_name=''
        ;;
    npm)
        image="node_local:__IMAGE_TAG__"
        image_command='npm'
        cache_name='node'
        ;;
    npx)
        image="node_local:__IMAGE_TAG__"
        image_command='npx'
        cache_name='node'
        ;;
    composer)
        image="composer_local:__IMAGE_TAG__"
        image_command='composer'
        cache_name='composer'
        ;;
esac

working_dir="$PWD"
interactive=()
if [[ -t 0 && -t 1 ]]; then
    interactive=(-it)
elif [[ ! -t 0 ]]; then
    interactive=(-i)
fi

user_options=(-u "$(id -u):$(id -g)")
docker_options=()
volume_options=(-v "$working_dir:$working_dir" -w "$working_dir")
environment_options=(-e SHELL=/bin/sh -e HOME=/tmp)

if [[ -n "$cache_name" ]]; then
    cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/locenv/$cache_name"
    mkdir -p "$cache_dir"

    case "$cache_name" in
        node)
            volume_options+=(-v "$cache_dir:/tmp/npm-cache")
            environment_options+=(-e npm_config_cache=/tmp/npm-cache)
            ;;
        composer)
            volume_options+=(-v "$cache_dir:/tmp/composer-home")
            environment_options+=(
                -e COMPOSER_HOME=/tmp/composer-home
                -e COMPOSER_CACHE_DIR=/tmp/composer-home/cache
            )
            ;;
    esac
fi

add_publish() {
    local mapping="$1"
    local host_port
    local container_port

    if [[ "$mapping" =~ ^[1-9][0-9]{0,4}:[1-9][0-9]{0,4}$ ]]; then
        host_port="${mapping%%:*}"
        container_port="${mapping##*:}"
    elif [[ "$mapping" =~ ^[1-9][0-9]{0,4}$ ]]; then
        host_port="$mapping"
        container_port="$mapping"
    else
        error "Invalid port mapping: $mapping. Use PORT or HOST_PORT:CONTAINER_PORT."
    fi

    if (( host_port > 65535 || container_port > 65535 )); then
        error 'Port values must be between 1 and 65535.'
    fi

    docker_options+=(-p "127.0.0.1:$host_port:$container_port")
}

for ((index = 0; index < ${#wrapper_options[@]}; index++)); do
    case "${wrapper_options[index]}" in
        --locenv-root)
            user_options=()
            ;;
        --locenv-port)
            (( index + 1 < ${#wrapper_options[@]} )) || error '--locenv-port requires a value.'
            add_publish "${wrapper_options[index + 1]}"
            index=$((index + 1))
            ;;
    esac
done

is_valid_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 ))
}

is_loopback_host() {
    case "$1" in
        ''|localhost|127.*|::1|\[::1\]) return 0 ;;
        *) return 1 ;;
    esac
}

parse_endpoint() {
    local endpoint="$1"
    ENDPOINT_HOST=''
    ENDPOINT_PORT=''

    case "$endpoint" in
        tcp://*|http://*|https://*) endpoint="${endpoint#*://}" ;;
    esac

    if [[ "$endpoint" =~ ^\[([^]]+)\]:([0-9]+)$ ]]; then
        ENDPOINT_HOST="${BASH_REMATCH[1]}"
        ENDPOINT_PORT="${BASH_REMATCH[2]}"
    elif [[ "$endpoint" =~ ^([^:]+):([0-9]+)$ ]]; then
        ENDPOINT_HOST="${BASH_REMATCH[1]}"
        ENDPOINT_PORT="${BASH_REMATCH[2]}"
    elif [[ "$endpoint" =~ ^:([0-9]+)$|^([0-9]+)$ ]]; then
        ENDPOINT_PORT="${BASH_REMATCH[1]:-${BASH_REMATCH[2]}}"
    else
        return 1
    fi

    is_valid_port "$ENDPOINT_PORT"
}

normalize_host() {
    if is_loopback_host "$1"; then
        printf '%s\n' '0.0.0.0'
    else
        printf '%s\n' "$1"
    fi
}

ensure_publish_for_port() {
    if [[ "$publish_requested" == false ]]; then
        add_publish "$1"
        publish_requested=true
    fi
}

append_server_args() {
    if [[ "$command_name" == npm && "${command_args[0]:-}" =~ ^(run|run-script|start)$ ]]; then
        if ! printf '%s\n' "${command_args[@]}" | grep -Fqx -- '--'; then
            command_args=("${command_args[0]}" "${command_args[1]:-}" -- "${command_args[@]:2}")
        fi
    fi
    command_args+=("$@")
}

set_adapter_spec() {
    case "$ADAPTER" in
        vite) HOST_LONG_FLAG='--host'; HOST_SHORT_FLAG=''; PORT_LONG_FLAG='--port'; PORT_SHORT_FLAG=''; SERVER_PORT=5173 ;;
        vite-preview) HOST_LONG_FLAG='--host'; HOST_SHORT_FLAG=''; PORT_LONG_FLAG='--port'; PORT_SHORT_FLAG=''; SERVER_PORT=4173 ;;
        next) HOST_LONG_FLAG='--hostname'; HOST_SHORT_FLAG='-H'; PORT_LONG_FLAG='--port'; PORT_SHORT_FLAG='-p'; SERVER_PORT=3000 ;;
        angular) HOST_LONG_FLAG='--host'; HOST_SHORT_FLAG=''; PORT_LONG_FLAG='--port'; PORT_SHORT_FLAG=''; SERVER_PORT=4200 ;;
        webpack|webpack-dev-server|rspack) HOST_LONG_FLAG='--host'; HOST_SHORT_FLAG=''; PORT_LONG_FLAG='--port'; PORT_SHORT_FLAG=''; SERVER_PORT=8080 ;;
        parcel) HOST_LONG_FLAG='--host'; HOST_SHORT_FLAG=''; PORT_LONG_FLAG='--port'; PORT_SHORT_FLAG=''; SERVER_PORT=1234 ;;
        storybook) HOST_LONG_FLAG='--host'; HOST_SHORT_FLAG='-h'; PORT_LONG_FLAG='--port'; PORT_SHORT_FLAG='-p'; SERVER_PORT=6006 ;;
        astro|nuxt|vue-cli-service|svelte-kit)
            HOST_LONG_FLAG='--host'; HOST_SHORT_FLAG=''; PORT_LONG_FLAG='--port'; PORT_SHORT_FLAG=''; SERVER_PORT=4321
            [[ "$ADAPTER" == nuxt ]] && SERVER_PORT=3000 || true
            [[ "$ADAPTER" == vue-cli-service ]] && SERVER_PORT=8080 || true
            [[ "$ADAPTER" == svelte-kit ]] && SERVER_PORT=5173 || true
            ;;
        react-scripts) HOST_LONG_FLAG='--host'; HOST_SHORT_FLAG=''; PORT_LONG_FLAG='--port'; PORT_SHORT_FLAG=''; SERVER_PORT=3000 ;;
        docusaurus|browser-sync) HOST_LONG_FLAG='--host'; HOST_SHORT_FLAG=''; PORT_LONG_FLAG='--port'; PORT_SHORT_FLAG=''; SERVER_PORT=3000 ;;
        wrangler) HOST_LONG_FLAG='--ip'; HOST_SHORT_FLAG=''; PORT_LONG_FLAG='--port'; PORT_SHORT_FLAG=''; SERVER_PORT=8787 ;;
        http-server) HOST_LONG_FLAG='--address'; HOST_SHORT_FLAG='-a'; PORT_LONG_FLAG='--port'; PORT_SHORT_FLAG='-p'; SERVER_PORT=8080 ;;
        serve) HOST_LONG_FLAG='--listen'; HOST_SHORT_FLAG='-l'; PORT_LONG_FLAG=''; PORT_SHORT_FLAG=''; SERVER_PORT=3000 ;;
        *) return 1 ;;
    esac
}

extract_port_from_args() {
    local -a arguments=("$@")
    local index argument value

    for ((index = 0; index < ${#arguments[@]}; index++)); do
        argument="${arguments[index]}"
        if [[ "$argument" == "$PORT_LONG_FLAG" || ( -n "$PORT_SHORT_FLAG" && "$argument" == "$PORT_SHORT_FLAG" ) ]]; then
            value="${arguments[index + 1]:-}"
            is_valid_port "$value" && SERVER_PORT="$value"
        elif [[ -n "$PORT_LONG_FLAG" && "$argument" == "$PORT_LONG_FLAG"=* ]]; then
            value="${argument#*=}"
            is_valid_port "$value" && SERVER_PORT="$value"
        fi
    done
}

normalize_standard_server_options() {
    local -a arguments=("${command_args[@]}")
    local index argument value normalized_host
    local has_host=false
    local has_port=false

    [[ -n "$HOST_LONG_FLAG" && -n "$PORT_LONG_FLAG" ]] || error "Adapter $ADAPTER does not support standard host/port options."

    for ((index = 0; index < ${#arguments[@]}; index++)); do
        argument="${arguments[index]}"
        if [[ "$argument" == "$HOST_LONG_FLAG" || ( -n "$HOST_SHORT_FLAG" && "$argument" == "$HOST_SHORT_FLAG" ) ]]; then
            has_host=true
            value="${arguments[index + 1]:-}"
            [[ -n "$value" && "$value" != -* ]] && command_args[index + 1]="$(normalize_host "$value")"
        elif [[ "$argument" == "$HOST_LONG_FLAG"=* ]]; then
            normalized_host="$(normalize_host "${argument#*=}")"
            command_args[index]="$HOST_LONG_FLAG=$normalized_host"
            has_host=true
        elif [[ "$argument" == "$PORT_LONG_FLAG" || ( -n "$PORT_SHORT_FLAG" && "$argument" == "$PORT_SHORT_FLAG" ) ]]; then
            has_port=true
            value="${arguments[index + 1]:-}"
            is_valid_port "$value" && SERVER_PORT="$value"
        elif [[ "$argument" == "$PORT_LONG_FLAG"=* ]]; then
            has_port=true
            value="${argument#*=}"
            is_valid_port "$value" && SERVER_PORT="$value"
        fi
    done

    is_valid_port "$SERVER_PORT" || error "Could not determine a valid port for adapter $ADAPTER. Use --locenv-port explicitly."
    ensure_publish_for_port "$SERVER_PORT"
    [[ "$has_host" == true ]] || append_server_args "$HOST_LONG_FLAG" '0.0.0.0'
    [[ "$has_port" == true ]] || append_server_args "$PORT_LONG_FLAG" "$SERVER_PORT"
    [[ "$ADAPTER" == react-scripts ]] && environment_options+=(-e HOST=0.0.0.0 -e PORT="$SERVER_PORT") || true
}

normalize_listen_options() {
    local -a arguments=("${command_args[@]}")
    local index argument value normalized_endpoint
    local has_listen=false

    for ((index = 0; index < ${#arguments[@]}; index++)); do
        argument="${arguments[index]}"
        if [[ "$argument" == '-l' || "$argument" == '--listen' ]]; then
            has_listen=true
            value="${arguments[index + 1]:-}"
            if parse_endpoint "$value"; then
                ensure_publish_for_port "$ENDPOINT_PORT"
                normalized_endpoint="$(normalize_host "$ENDPOINT_HOST"):$ENDPOINT_PORT"
                command_args[index + 1]="$normalized_endpoint"
                SERVER_PORT="$ENDPOINT_PORT"
            fi
        elif [[ "$argument" == '--listen='* ]]; then
            has_listen=true
            if parse_endpoint "${argument#*=}"; then
                ensure_publish_for_port "$ENDPOINT_PORT"
                normalized_endpoint="$(normalize_host "$ENDPOINT_HOST"):$ENDPOINT_PORT"
                command_args[index]="--listen=$normalized_endpoint"
                SERVER_PORT="$ENDPOINT_PORT"
            fi
        fi
    done

    if [[ "$has_listen" == false ]]; then
        is_valid_port "$SERVER_PORT" || error "Could not determine a valid port for adapter $ADAPTER. Use --locenv-port explicitly."
        ensure_publish_for_port "$SERVER_PORT"
        append_server_args '--listen' "0.0.0.0:$SERVER_PORT"
    fi
}

adapt_php_server() {
    local -a arguments=("${command_args[@]}")
    local index argument endpoint normalized_endpoint

    for ((index = 0; index < ${#arguments[@]}; index++)); do
        argument="${arguments[index]}"
        if [[ "$argument" == '-S' ]]; then
            endpoint="${arguments[index + 1]:-}"
            if parse_endpoint "$endpoint"; then
                ensure_publish_for_port "$ENDPOINT_PORT"
                normalized_endpoint="$(normalize_host "$ENDPOINT_HOST"):$ENDPOINT_PORT"
                command_args[index + 1]="$normalized_endpoint"
            fi
            return 0
        elif [[ "$argument" == -S* && "$argument" != '-S' ]]; then
            endpoint="${argument#-S}"
            if parse_endpoint "$endpoint"; then
                ensure_publish_for_port "$ENDPOINT_PORT"
                normalized_endpoint="$(normalize_host "$ENDPOINT_HOST"):$ENDPOINT_PORT"
                command_args[index]="-S$normalized_endpoint"
            fi
            return 0
        fi
    done
}

detect_adapter_from_args() {
    local -a arguments=("$@")
    local index subcommand base argument
    ADAPTER=''

    for ((index = 0; index < ${#arguments[@]}; index++)); do
        argument="${arguments[index]}"
        base="${argument##*/}"
        base="${base%.js}"
        base="${base%.cjs}"
        base="${base%.mjs}"

        case "$base" in
            vite)
                subcommand="${arguments[index + 1]:-}"
                [[ "$subcommand" == build ]] && continue
                [[ "$subcommand" == preview ]] && ADAPTER='vite-preview' || ADAPTER='vite'
                return 0
                ;;
            next)
                for ((subcommand = index + 1; subcommand < ${#arguments[@]}; subcommand++)); do
                    [[ "${arguments[subcommand]}" == dev || "${arguments[subcommand]}" == start ]] && ADAPTER='next' && return 0
                done
                ;;
            ng)
                [[ "${arguments[index + 1]:-}" == serve ]] && ADAPTER='angular' && return 0
                ;;
            webpack|webpack-dev-server|rspack)
                if [[ "$base" == webpack || "$base" == rspack ]]; then
                    [[ "${arguments[index + 1]:-}" != serve ]] && continue
                fi
                ADAPTER="$base"
                return 0
                ;;
            parcel)
                [[ "${arguments[index + 1]:-}" == build ]] && continue
                ADAPTER='parcel'
                return 0
                ;;
            storybook)
                [[ "${arguments[index + 1]:-}" == dev || "${arguments[index + 1]:-}" == start ]] && ADAPTER='storybook' && return 0
                ;;
            astro)
                [[ "${arguments[index + 1]:-}" == dev || "${arguments[index + 1]:-}" == preview ]] && ADAPTER='astro' && return 0
                ;;
            nuxt)
                [[ "${arguments[index + 1]:-}" == dev || "${arguments[index + 1]:-}" == start || "${arguments[index + 1]:-}" == preview ]] && ADAPTER='nuxt' && return 0
                ;;
            vue-cli-service)
                [[ "${arguments[index + 1]:-}" == serve ]] && ADAPTER='vue-cli-service' && return 0
                ;;
            react-scripts)
                [[ "${arguments[index + 1]:-}" == start ]] && ADAPTER='react-scripts' && return 0
                ;;
            docusaurus)
                [[ "${arguments[index + 1]:-}" == start || "${arguments[index + 1]:-}" == serve ]] && ADAPTER='docusaurus' && return 0
                ;;
            wrangler)
                [[ "${arguments[index + 1]:-}" == dev ]] && ADAPTER='wrangler' && return 0
                ;;
            serve)
                ADAPTER='serve'
                return 0
                ;;
            http-server)
                ADAPTER='http-server'
                return 0
                ;;
            browser-sync)
                [[ "${arguments[index + 1]:-}" == start ]] && ADAPTER='browser-sync' && return 0
                ;;
        esac
    done

    return 1
}

read_npm_script() {
    local script_name="$1"
    [[ -f "$working_dir/package.json" ]] || return 1

    docker run --rm -v "$working_dir:/workspace:ro" -w /workspace "$image" \
        node -e "const fs=require(\"fs\"); const p=JSON.parse(fs.readFileSync(\"package.json\",\"utf8\")); const script=p.scripts?.[process.argv[1]]; if (script) process.stdout.write(script);" \
        "$script_name" 2>/dev/null
}

detect_npm_adapter() {
    local script_name script_text
    local -a script_arguments=()

    case "${command_args[0]:-}" in
        run|run-script) script_name="${command_args[1]:-}" ;;
        start) script_name='start' ;;
        exec|x) detect_adapter_from_args "${command_args[@]:1}" || true; return 0 ;;
        *) return 0 ;;
    esac

    [[ -n "${script_name:-}" ]] || return 0
    script_text="$(read_npm_script "$script_name" || true)"
    [[ -n "$script_text" ]] || return 0

    read -r -a script_arguments <<< "$script_text"
    detect_adapter_from_args "${script_arguments[@]}" || true
    [[ -n "$ADAPTER" ]] || return 0
    set_adapter_spec
    extract_port_from_args "${script_arguments[@]}"
}

ADAPTER=''
SERVER_PORT=''
HOST_LONG_FLAG=''
HOST_SHORT_FLAG=''
PORT_LONG_FLAG=''
PORT_SHORT_FLAG=''

case "$command_name" in
    php) adapt_php_server ;;
    node|npx) detect_adapter_from_args "${command_args[@]}" || true ;;
    npm) detect_npm_adapter ;;
esac

if [[ -n "$ADAPTER" ]]; then
    set_adapter_spec
    if [[ "$ADAPTER" == serve ]]; then
        normalize_listen_options
    else
        normalize_standard_server_options
    fi
fi

exec docker run --rm \
    "${interactive[@]}" \
    "${user_options[@]}" \
    "${docker_options[@]}" \
    "${volume_options[@]}" \
    "${environment_options[@]}" \
    "$image" \
    "$image_command" \
    "${command_args[@]}"
DISPATCHER
)

SHIM=$(cat <<'SHIM'
#!/usr/bin/env bash

set -Eeuo pipefail

command_name="${0##*/}"
dispatcher="${HOME:?HOME is not set}/.local/bin/.locenv-dispatcher"

if [[ ! -x "$dispatcher" ]]; then
    printf 'locenv: dispatcher not found: %s\n' "$dispatcher" >&2
    printf 'Run build.sh to install or repair the environment.\n' >&2
    exit 1
fi

exec "$dispatcher" "$command_name" "$@"
SHIM
)

write_file() {
    local destination="$1"
    local content="$2"
    local temporary_file

    temporary_file="$(mktemp "${destination}.XXXXXX")"
    printf '%s\n' "$content" > "$temporary_file"
    chmod 755 "$temporary_file"
    mv -f "$temporary_file" "$destination"
}

for file in "${selected_files[@]}"; do
    content="$SHIM"
    write_file "$BIN_PATH/$file" "$content"
done

write_file "$BIN_PATH/.locenv-dispatcher" "${DISPATCHER//__IMAGE_TAG__/$IMAGE_TAG}"

shell_name="${SHELL##*/}"
case "$shell_name" in
    zsh) shell_rc="$HOME/.zshrc" ;;
    bash) shell_rc="$HOME/.bashrc" ;;
    *) shell_rc="$HOME/.profile" ;;
esac

touch "$shell_rc"

append_shell_line() {
    local line="$1"
    if ! grep -Fqx "$line" "$shell_rc"; then
        printf '%s\n' "$line" >> "$shell_rc"
    fi
}

append_shell_line 'export PATH="$HOME/.local/bin:$PATH"'

printf '\nInstalled shims in %s:\n' "$BIN_PATH"
for file in "${selected_files[@]}"; do
    printf '  %s\n' "$file"
done

printf '\nShell configuration updated: %s\n' "$shell_rc"
printf 'Open a new shell or run: . %s\n' "$shell_rc"
