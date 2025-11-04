#!/bin/sh
# Wave installer script
# Usage: curl -fsSL https://raw.githubusercontent.com/Wuffz/wave/main/bin/install.sh | sh

set -e

WAVE_URL="https://raw.githubusercontent.com/Wuffz/wave/main/bin/wave.sh"

echo "Installing Wave..."
echo ""

# Ask user for installation preference
if [ -t 0 ]; then
  # Interactive mode
  echo "Choose installation type:"
  echo "  1) User install (~/.local/bin) - No root required"
  echo "  2) Global install (/usr/local/bin) - Requires root"
  echo ""
  printf "Enter choice [1]: "
  read -r CHOICE
  CHOICE=${CHOICE:-1}
else
  # Non-interactive mode (piped input), default to user install
  CHOICE=1
fi

if [ "$CHOICE" = "2" ]; then
  # Global install
  INSTALL_DIR="/usr/local/bin"
  SUDO=""

  if [ ! -w "$INSTALL_DIR" ]; then
    if command -v sudo >/dev/null 2>&1; then
      SUDO="sudo"
      echo "Need sudo permissions to install to $INSTALL_DIR"
    else
      echo "Error: Cannot write to $INSTALL_DIR and sudo is not available"
      exit 1
    fi
  fi
else
  # User install
  INSTALL_DIR="$HOME/.local/bin"
  SUDO=""

  # Create directory if it doesn't exist
  mkdir -p "$INSTALL_DIR"

  # Check if directory is in PATH
  case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *)
      echo "Note: $INSTALL_DIR is not in your PATH"
      echo "Add this to your ~/.bashrc or ~/.zshrc:"
      echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
      echo ""
      ;;
  esac
fi

WAVE_BIN="$INSTALL_DIR/wave"

# Test write permissions before downloading
if [ -z "$SUDO" ]; then
  # No sudo, test if we can write to the target file
  if ! echo "" > "$WAVE_BIN" 2>/dev/null; then
    echo "Error: Cannot write to $WAVE_BIN"
    echo "Please run with appropriate permissions or choose a different installation location"
    exit 1
  fi
  # Clean up test file
  rm -f "$WAVE_BIN"
fi

# Download wave
echo "Downloading wave from GitHub..."
if command -v curl >/dev/null 2>&1; then
  $SUDO curl -fsSL "$WAVE_URL" -o "$WAVE_BIN" || {
    echo "Error: Failed to download wave"
    exit 1
  }
elif command -v wget >/dev/null 2>&1; then
  $SUDO wget -q "$WAVE_URL" -O "$WAVE_BIN" || {
    echo "Error: Failed to download wave"
    exit 1
  }
else
  echo "Error: Neither curl nor wget is available"
  echo "Please install curl or wget and try again"
  exit 1
fi

# Make it executable
echo "Making wave executable..."
$SUDO chmod +x "$WAVE_BIN" || {
  echo "Error: Failed to make wave executable"
  exit 1
}

# Verify installation
if [ -x "$WAVE_BIN" ]; then
  echo "Wave installed successfully to $WAVE_BIN"
  echo ""
  echo "Get started:"
  echo "  cd your-git-repo"
  echo "  wave init"
  echo "  wave create feature-branch"
  echo ""
  echo "For more information, visit: https://github.com/Wuffz/wave"
else
  echo "Error: Installation failed"
  exit 1
fi

