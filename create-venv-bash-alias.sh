#!/bin/bash

os=$(uname | tr '[:upper:]' '[:lower:]')
rc_file=~/.bashrc
shell=bash

if [[ $os == darwin* ]]; then
    rc_file=~/.zshrc
    shell=zsh
elif [[ $os != linux* ]]; then
    echo "Unknown OS"
    exit 1
fi

venv_file="python-venv-setup.sh"

if [ ! -f "$PWD/$venv_file" ]; then
    echo "$venv_file file not found in $PWD"
    exit 1
fi

sed -i '/alias mkvenv="/d' $rc_file # remove alias

venv_file_path="$PWD/$venv_file"
alias_cmd="alias mkvenv=\"$venv_file_path\""
grep -q "$alias_cmd" "$rc_file" || echo "$alias_cmd" >> "$rc_file"

chmod +x "$venv_file_path"
chown "$SUDO_USER:$SUDO_USER" "$venv_file_path"

exec "$shell"