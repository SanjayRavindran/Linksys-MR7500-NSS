#!/usr/bin/env bash
# ==============================================================================
# Linksys MR7500 (Hydra Pro 6E) OpenWrt + NSS Build Environment Setup
# Supported Host: Ubuntu 22.04 LTS / 24.04 LTS / 26.04 LTS
# ==============================================================================
set -e

echo "=== 1. Installing OpenWrt build packages & utilities ==="
sudo apt-get update
sudo apt-get install -y \
    build-essential clang flex bison g++ gawk gettext git \
    libncurses-dev libssl-dev python3 python3-setuptools python3-pyelftools \
    rsync swig unzip zlib1g-dev file wget curl \
    device-tree-compiler squashfs-tools u-boot-tools \
    iperf3 ccache xz-utils zstd bzip2 patch perl bc time

# Install GCC 14 on newer Ubuntu releases (Ubuntu 24.04+ defaults to GCC 14/15)
if dpkg --compare-versions "$(lsb_release -rs 2>/dev/null || echo 22.04)" "ge" "24.04"; then
    echo "=== 2. Configuring GCC 14 for OpenWrt host compatibility ==="
    sudo apt-get install -y gcc-14 g++-14 || true
    if command -v gcc-14 >/dev/null 2>&1; then
        HOSTCC_DIR="$HOME/.local/openwrt-hostcc"
        mkdir -p "$HOSTCC_DIR"
        ln -sf "$(command -v gcc-14)" "$HOSTCC_DIR/gcc"
        ln -sf "$(command -v g++-14)" "$HOSTCC_DIR/g++"
        ln -sf "$(command -v gcc-14)" "$HOSTCC_DIR/cc"
        ln -sf "$(command -v g++-14)" "$HOSTCC_DIR/c++"
        echo "Created GCC 14 wrapper in $HOSTCC_DIR"
        echo "Add to PATH when building: export PATH=\"$HOSTCC_DIR:\$PATH\""
    fi
fi

echo "=== Build environment setup complete! ==="
