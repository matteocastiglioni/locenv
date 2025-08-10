#!/bin/bash

# cleanup previous installations
if [ -f cuda-keyring_1.1-1_all.deb ]; then
    echo "Removing old cuda-keyring_1.1-1_all.deb"
    rm cuda-keyring_1.1-1_all.deb
fi
if [ -f cuda-keyring_1.1-1_all.deb.1 ]; then
    echo "Removing old cuda-keyring_1.1-1_all.deb.1"
    rm cuda-keyring_1.1-1_all.deb.1
fi

if command -v nvcc >/dev/null 2>&1; then
    echo "CUDA Toolkit is already installed"
    exit 0
fi

echo "Installing CUDA Toolkit 12.8 for WSL Ubuntu"

wget https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt-get update
sudo apt-get -y install cuda-toolkit-12-8

if [ ! -L /usr/lib/wsl/lib/nvcc ]; then
    sudo ln -s /usr/local/cuda-12.8/bin/nvcc /usr/lib/wsl/lib/nvcc
fi

which nvcc
nvcc --version

which nvidia-smi
nvidia-smi


