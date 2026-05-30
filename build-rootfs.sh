#!/bin/bash
set -euo pipefail

WORK_DIR="$GITHUB_WORKSPACE/build"
ROOTFS_DIR="${WORK_DIR}/rootfs"
IMG_FILE="${WORK_DIR}/rootfs_128m.ext4"
MNT_DIR="${WORK_DIR}/mnt"

# 初始化目录
rm -rf "${WORK_DIR}"
mkdir -p "${ROOTFS_DIR}" "${MNT_DIR}"

# 安装依赖
apt update -y
apt install -y debootstrap qemu-user-static binfmt-support e2fsprogs

# 拉取 Debian 12 Bookworm armhf
debootstrap --arch=armhf bookworm "${ROOTFS_DIR}" https://mirrors.ustc.edu.cn/debian/

# 挂载系统目录 + 注入 qemu
cp /usr/bin/qemu-arm-static "${ROOTFS_DIR}/usr/bin/"
mount --bind /dev "${ROOTFS_DIR}/dev"
mount --bind /proc "${ROOTFS_DIR}/proc"
mount --bind /sys "${ROOTFS_DIR}/sys"

# Chroot 配置系统
chroot "${ROOTFS_DIR}" << EOF
cat > /etc/apt/sources.list << SRC
deb https://mirrors.ustc.edu.cn/debian/ bookworm main contrib non-free
deb https://mirrors.ustc.edu.cn/debian/ bookworm-updates main contrib non-free
deb https://mirrors.ustc.edu.cn/debian/ bookworm-security main contrib non-free
SRC

apt update -y
apt install -y systemd openssh-server net-tools iproute2 vim less

# 启用串口 ttyAMA0
echo "ttyAMA0" >> /etc/securetty
systemctl enable getty@ttyAMA0.service

# 允许 root SSH 登录
sed -i 's/^#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
systemctl enable ssh

# 主机名、DNS
echo "hi3798mv100" > /etc/hostname
echo "127.0.0.1   localhost hi3798mv100" > /etc/hosts
echo "nameserver 114.114.114.114" > /etc/resolv.conf

# 清理海纳思残留
rm -f /etc/nasversion
rm -rf /usr/local/bin/histb* /etc/init.d/histb*

# root 密码
echo "root:123456" | chpasswd

# 清理缓存
apt clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
EOF

# 解除绑定挂载
umount "${ROOTFS_DIR}/dev" "${ROOTFS_DIR}/proc" "${ROOTFS_DIR}/sys"

# 生成 128M ext4 镜像
dd if=/dev/zero of="${IMG_FILE}" bs=1M count=128
mkfs.ext4 -F "${IMG_FILE}"

# 写入文件
mount "${IMG_FILE}" "${MNT_DIR}"
cp -a "${ROOTFS_DIR}"/* "${MNT_DIR}/"
umount "${MNT_DIR}"

echo "Done: ${IMG_FILE}"
