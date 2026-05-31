#!/bin/bash
set -euo pipefail

# ===================== 配置项 =====================
# 目标系统版本、架构、根目录
TARGET_SUITE="focal"
TARGET_ARCH="armhf"
ROOTFS_DIR="./ubuntu-focal-armhf-rootfs"
# 优先使用 old-releases 兼容源，解决 focal 架构包拉取失败
UBUNTU_MIRROR="http://old-releases.ubuntu.com/ubuntu"
# ===================================================

echo "=== Start build ${TARGET_SUITE} ${TARGET_ARCH} rootfs ==="

# 1. 清理旧目录
if [ -d "${ROOTFS_DIR}" ]; then
    echo "Clean old rootfs dir: ${ROOTFS_DIR}"
    rm -rf "${ROOTFS_DIR}"
fi

# 2. 安装依赖
echo "Install dependencies..."
apt update -y
apt install -y binfmt-support debootstrap qemu-user-static

# 3. 启用 binfmt 跨架构支持
echo "Enable binfmt for ${TARGET_ARCH}"
systemctl restart binfmt-support

# 4. debootstrap 构建 rootfs（关键修复参数）
echo "Start debootstrap..."
debootstrap \
    --arch="${TARGET_ARCH}" \
    --variant=minbase \
    --force \
    --no-check-gpg \
    --components=main,universe,restricted,multiverse \
    "${TARGET_SUITE}" \
    "${ROOTFS_DIR}" \
    "${UBUNTU_MIRROR}"

echo "=== Rootfs build completed successfully ==="
