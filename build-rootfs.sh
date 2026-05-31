#!/bin/bash
set -euo pipefail

# ===================== 配置项 =====================
TARGET_SUITE="focal"
TARGET_ARCH="armhf"
ROOTFS_DIR="./ubuntu-focal-armhf-rootfs"
UBUNTU_MIRROR="http://old-releases.ubuntu.com/ubuntu"
# ===================================================

echo "=== Start build ${TARGET_SUITE} ${TARGET_ARCH} rootfs ==="

# 清理旧目录
if [ -d "${ROOTFS_DIR}" ]; then
    echo "Clean old rootfs dir: ${ROOTFS_DIR}"
    rm -rf "${ROOTFS_DIR}"
fi

# 安装依赖（加上 sudo）
echo "Install dependencies..."
sudo apt update -y
sudo apt install -y binfmt-support debootstrap qemu-user-static

# 启用 binfmt 跨架构支持
echo "Enable binfmt for ${TARGET_ARCH}"
sudo systemctl restart binfmt-support

# 构建 rootfs
echo "Start debootstrap..."
sudo debootstrap \
    --arch="${TARGET_ARCH}" \
    --variant=minbase \
    --force \
    --no-check-gpg \
    --components=main,universe,restricted,multiverse \
    "${TARGET_SUITE}" \
    "${ROOTFS_DIR}" \
    "${UBUNTU_MIRROR}"

echo "=== Rootfs build completed successfully ==="
