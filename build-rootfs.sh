#!/bin/bash
set -euo pipefail

WORK_DIR="$GITHUB_WORKSPACE/build"
ROOTFS_DIR="${WORK_DIR}/rootfs"
IMG_FILE="${WORK_DIR}/rootfs_128m.ext4"
MNT_DIR="${WORK_DIR}/mnt"

# 清理旧文件
rm -rf "${WORK_DIR}"
mkdir -p "${ROOTFS_DIR}" "${MNT_DIR}"

# 安装依赖
sudo apt update -y
sudo apt install -y debootstrap qemu-user-static binfmt-support e2fsprogs

# -------------------------------------------------
# 【核心变更】拉取 Ubuntu 24.04 LTS (Noble) armhf
# -------------------------------------------------
sudo debootstrap --arch=armhf noble "${ROOTFS_DIR}" https://mirrors.ustc.edu.cn/ubuntu/

# 注入 qemu
sudo cp /usr/bin/qemu-arm-static "${ROOTFS_DIR}/usr/bin/"

# 绑定基础目录
sudo mount --bind /dev "${ROOTFS_DIR}/dev"
sudo mount --bind /proc "${ROOTFS_DIR}/proc"
sudo mount --bind /sys "${ROOTFS_DIR}/sys"
sudo mount --bind /dev/pts "${ROOTFS_DIR}/dev/pts"

# 拷贝Overlay配置
echo ">>> 拷贝系统预置配置(网络/MAC)"
sudo cp -r "${GITHUB_WORKSPACE}/overlay"/* "${ROOTFS_DIR}/"
sudo chmod 644 "${ROOTFS_DIR}/etc/network/interfaces"

# Chroot 配置系统
sudo chroot "${ROOTFS_DIR}" << 'EOF'
# 修复软件源：Ubuntu 24.04 源配置
cat > /etc/apt/sources.list << 'SRC'
deb https://mirrors.ustc.edu.cn/ubuntu-ports/ noble main restricted universe multiverse
deb https://mirrors.ustc.edu.cn/ubuntu-ports/ noble-security main restricted universe multiverse
deb https://mirrors.ustc.edu.cn/ubuntu-ports/ noble-updates main restricted universe multiverse
SRC

# 设置时区与环境
export TZ=Asia/Shanghai
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
echo "Asia/Shanghai" > /etc/timezone
# Ubuntu 24.04 可能需要安装 tzdata 包来静默配置
DEBIAN_FRONTEND=noninteractive apt install -y tzdata

# 配置基础工具与 SSH
apt update -y
apt install -y systemd openssh-server net-tools iproute2 vim less \
curl wget dnsutils lsof rsync tree unzip zip xz-utils procps

# 允许 root SSH 登录
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
systemctl enable ssh

# 主机名、DNS 与 MAC (假设 MAC 设置在 overlay 或 interfaces 中)
echo "hi3798mv100" > /etc/hostname
echo "127.0.0.1   localhost hi3798mv100" > /etc/hosts
echo "nameserver 114.114.114.114" > /etc/resolv.conf

# 设置 root 密码
echo "root:123456" | chpasswd

# 启用串口与网络
echo "ttyAMA0" >> /etc/securetty
systemctl enable getty@ttyAMA0.service
systemctl enable networking

# 清理
apt clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/locale/*
EOF

# 解除挂载
sudo umount "${ROOTFS_DIR}/dev/pts"
sudo umount "${ROOTFS_DIR}/dev" "${ROOTFS_DIR}/proc" "${ROOTFS_DIR}/sys"

# 制作镜像 (保持原有 256M 大小)
sudo dd if=/dev/zero of="${IMG_FILE}" bs=1M count=256
sudo mkfs.ext4 -F "${IMG_FILE}"

# 拷贝文件到镜像
sudo mount "${IMG_FILE}" "${MNT_DIR}"
sudo cp -a "${ROOTFS_DIR}"/* "${MNT_DIR}/"
sudo umount "${MNT_DIR}"

echo "====================================="
echo "  Ubuntu 24.04 LTS 构建完成"
echo "  镜像: ${IMG_FILE}"
echo "  账号: root  密码: 123456"
echo "  网卡: eth0 自动DHCP  MAC: BC:25:E0:3F:F1:D9"
echo "====================================="
