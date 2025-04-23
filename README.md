# Docker Local Development Environment

A lightweight Docker-based development environment that provides isolated CLI tools without installing them directly on your system.

## Features

- Containerized development tools
- Automatic PATH configuration
- Interactive and non-interactive modes
- User permission handling
- Support for Ubuntu and macOS
- Python virtual environment management
- Ollama AI integration

## Available Tools

- PHP 8 (`php`)
- Node.js LTS (`node`, `npm`, `npx`) 
- Composer (`composer`)
- Git 2.47.2 (`git`) with environment configuration
- Python 3.12 (`python`, `pip`)
- Ollama AI (`ollama`)

## System Requirements

- Docker Engine 24.0 or later
- Ubuntu 22.04+ or macOS 12+
- Bash (Ubuntu) or Zsh (macOS)
- NVIDIA drivers (optional, for GPU support with Ollama)

## Installation

1. Clone this repository

2. Configure Git environment:
```bash
cp .env.example .env
```
Edit `.env` with your Git configuration:
```ini
GIT_EMAIL="your.email@example.com"
GIT_USERNAME="Your Name"
```

3. Run the build script:
```bash
./build.sh
```

The script will:
- Build Docker images for each tool
- Create executable wrappers in `~/.local/bin` directory
- Add the `~/.local/bin` directory to your PATH (permanently in `~/.bashrc` or `~/.zshrc`)
- Add Docker convenience aliases (`dk` for docker and `dkc` for docker compose)
- Configure Git with settings from `.env` if present
- Automatic shell reload after installation

## Usage

After installation, you can use any of the tools directly from your terminal:

```bash
# PHP
php --version
php -S 0.0.0.0:8000

# Node.js
node --version
npm install

# Python
python script.py
pip install requests

# Commit using configured identity
git commit -m "Update readme"

# Ollama AI
ollama run llama3
```

### Command Options

Each command (except `ollama`) supports these options:

- `--int`: Force interactive mode
- `--root`: Run as root inside container
- `--port PORT`: Map a specific port

Example:
```bash
# Run PHP development server
php --port 8000 -S 0.0.0.0:8000

# Run Python in interactive mode
python --int

# Install npm packages as root
npm --root install
```

### Ollama Command

The `ollama` command provides special handling for AI model management:

- Automatic service management
- GPU support auto-detection
- Full command set support (serve, create, run, etc.)

## Additional Scripts

### Python Virtual Environment Setup

The repository includes scripts to help manage Python virtual environments:

#### python-venv-setup.sh
A script to create and configure Python virtual environments:
```bash
# Create a new virtual environment in the current directory
./python-venv-setup.sh
```

Features:
- Creates `.venv` directory in current project
- Auto-installs required dependencies (python3-venv, pip) if missing
- Configures Python interpreter symlinks
- Interactive setup process
- Provides clear activation/deactivation instructions

#### create-venv-bash-alias.sh
Creates a system-wide `mkvenv` alias for easy virtual environment setup:
```bash
# Install the mkvenv alias
./create-venv-bash-alias.sh

# Usage after installation
mkvenv
```

Features:
- Adds permanent alias to `~/.bashrc` or `~/.zshrc`
- Cross-platform support (Ubuntu/macOS)
- Automatic shell reload after installation

### Ollama Setup Script without Docker
The `ollama-setup.sh` script is designed for users who want to install Ollama without Docker:

```bash
./ollama-setup.sh
```

Features:
- Interactive menu with options:
  1. Install: Fresh Ollama installation
  2. Reinstall: Remove and reinstall Ollama
  3. Uninstall: Complete removal including services and user
- Handles system services and cleanup
- Compatible with Ubuntu systems

## Troubleshooting

For path-related issues, verify that `~/.local/bin` is in your PATH:
```bash
echo $PATH | grep localenvbin
```