#!/bin/bash

choice="y"

if [ -d ".venv" ]; then
    echo -e 'There is already a virtual environment, if you proceed it will be removed'
    read -p "Do you want to continue? (y/n): " choice
fi

if [[ $choice == [Yy]* ]]; then
    echo -e 'The virtual environment will be created in \033[1;32m"'$PWD'/.venv"\033[0m'
    read -p "Do you want to continue? (y/n): " choice

    if [[ $choice == [Yy]* ]]; then
        if ! python -m venv --help &> /dev/null; then
            echo "The Python venv module is not available"
            read -p "Do you want to install the venv module? (y/n): " choice

            if [[ $choice == [Yy]* ]]; then
                echo "Installing python3-venv..."

                sudo apt-get update
                sudo apt-get install -y python3-venv

                echo "Python venv module installed successfully"
            fi
        fi

        if ! command -v pip &> /dev/null; then
            echo "pip is not available"
            read -p "Do you want to install pip? (y/n): " choice

            if [[ $choice == [Yy]* ]]; then
                echo "Installing pip..."

                sudo apt-get update
                sudo apt-get install -y python3-pip

                echo "pip installed successfully"
            fi
        fi

        if [ -d ".venv" ]; then
            echo "Removing existing virtual environment..."
            rm -rf .venv
            echo "Existing virtual environment removed"
        fi

        echo "Creating virtual environment..."
        python -m venv .venv
        echo "Virtual environment created successfully"

        # if [ -L ".venv/bin/python" ]; then
        #     rm .venv/bin/python
        # fi
        # ln -s ${LOCAL_BIN_PATH:-$(which python)} .venv/bin/python

        echo -e '\nTo activate the virtual environment, run \033[1;32m"source .venv/bin/activate"\033[0m in \033[1;32m"'$PWD'"\033[0m.'
        echo -e 'To deactivate the virtual environment, run \033[1;32m"deactivate"\033[0m in \033[1;32m"'$PWD'"\033[0m.'
        echo -e "To install the required packages, run \033[1;32m"pip install -r requirements.txt"\033[0m inside the virtual environment."
    fi
fi
