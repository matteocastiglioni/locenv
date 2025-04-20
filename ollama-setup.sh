#!/bin/bash

echo "Please choose an option:"
echo "1) Install"
echo "2) Reinstall"
echo "3) Uninstall"
read -p "Enter your choice (1-3): " choice

case $choice in
  1)
    echo "Installing..."

    curl -fsSL https://ollama.com/install.sh | sh
    ;;
  2)
    echo "Reinstalling..."

    curl -fsSL https://ollama.com/install.sh | sh
    ;;
  3)
    echo "Uninstalling..."
    
    sudo systemctl stop ollama
    sudo systemctl disable ollama
    sudo rm /etc/systemd/system/ollama.service

    sudo rm $(which ollama)

    sudo rm -r /usr/share/ollama
    sudo userdel ollama
    sudo groupdel ollama

    sudo rm -rf /usr/local/lib/ollama
    ;;
  *)
    echo "Invalid choice. Exiting."
    exit 1
    ;;
esac

exit 0
