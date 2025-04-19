# Docker Local Development Environment

A lightweight Docker-based development environment that provides isolated CLI tools without installing them directly on your system.

## Features

- Containerized development tools
- Automatic PATH configuration
- Interactive and non-interactive modes
- User permission handling
- Support for Ubuntu and macOS

## Available Tools

- PHP 8 (`php`)
- Node.js LTS (`node`, `npm`, `npx`) 
- Composer (`composer`)
- Git 2.47.2 (`git`)
- Python 3.12 (`python`, `pip`)
- Ollama AI (`ollama`)

## Installation

1. Clone this repository
2. Run the build script:
```bash
./build.sh
```

The script will:
- Build Docker images for each tool
- Create executable wrappers in `.bin` directory
- Add the `.bin` directory to your PATH
- Add Docker convenience aliases (`dk` and `dkc`)

## Usage

After installation, you can use any of the tools directly from your terminal:

```bash
# Run PHP
php --version

# Use Node.js
node --version
npm install
npx create-react-app myapp

# Run Python
python script.py
pip install requests

# Use Ollama AI
ollama run llama2
```

### Command Options

Each command (except `ollama`) supports these options:

- `--int`: Force interactive mode
- `--root`: Run as root inside container
- `--port PORT`: Map a specific port

Example:
```bash
php --port 8000 -S 0.0.0.0:8000
```

## Ollama Integration

The `ollama` command provides special handling for AI model management:

- Automatic service management
- GPU support detection
- Full command set support (serve, create, run, etc.)

## System Requirements

- Docker
- Ubuntu or macOS
- Bash (Ubuntu) or Zsh (macOS)
- NVIDIA drivers (optional, for GPU support with Ollama)