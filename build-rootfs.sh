#!/bin/bash
set -euo pipefail

# 配置项
TARGET_SUITE="focal"
TARGET_ARCH="armhf"
ROOTFS_DIR="./ubuntu-focal-armhf-rootfs"
# 改用中科大旧版Ubuntu镜像，适配CI网络
UBUNTU_MIRROR="https://mirrors.ustc.edu.cn/ubuntu-old-releases/ubuntu"

echo "=== Start build ${TARGET_SUITE} ${TARGET_ARCH} rootfs ==="

# 清理旧目录
if [ -d "${ROOTFS_DIR}" ]; then
    echo "Clean old rootfs dir: ${ROOTFS_DIR}"
    rm -rf "${ROOTFS_DIR}"
fi

# 安装依赖
echo "Install dependencies..."
sudo apt update -y
sudo apt install -y binfmt-support debootstrap qemu-user-static

# 启用跨架构执行
echo "Enable binfmt for ${TARGET_ARCH}"
sudo systemctl restart binfmt-support

# 构建 rootfs
echo "Start debootstrap..."
sudo debootstrap \
    --arch="${TARGET_ARCH}" \
    --variant=minbase \
    --no-check-gpg \
    --components=main,universe,restricted,multiverse \
    "${TARGET_SUITE}" \
    "${ROOTFS_DIR}" \
    "${UBUNTU_MIRROR}"

echo "=== Rootfs build completed successfully ==="
