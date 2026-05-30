#!/bin/bash
set -euo pipefail

WORK_DIR="$GITHUB_WORKSPACE/build"
ROOTFS_DIR="${WORK_DIR}/rootfs"
# 镜像扩容为 256M
IMG_FILE="${WORK_DIR}/rootfs_128m.ext4"
MNT_DIR="${WORK_DIR}/mnt"

# 清理旧文件
rm -rf "${WORK_DIR}"
mkdir -p "${ROOTFS_DIR}" "${MNT_DIR}"

# 安装依赖
sudo apt update -y
sudo apt install -y debootstrap qemu-user-static binfmt-support e2fsprogs

# 拉取 Debian 12 Bookworm armhf
sudo debootstrap --arch=armhf bookworm "${ROOTFS_DIR}" https://mirrors.ustc.edu.cn/debian/

# 注入 qemu
sudo cp /usr/bin/qemu-arm-static "${ROOTFS_DIR}/usr/bin/"

# 绑定基础目录 + 新增 pts 解决终端/日志报错
sudo mount --bind /dev "${ROOTFS_DIR}/dev"
sudo mount --bind /proc "${ROOTFS_DIR}/proc"
sudo mount --bind /sys "${ROOTFS_DIR}/sys"
sudo mount --bind /dev/pts "${ROOTFS_DIR}/dev/pts"

# Chroot 配置系统
sudo chroot "${ROOTFS_DIR}" << EOF
# 修复软件源：移除失效 security 单独源
cat > /etc/apt/sources.list << SRC
deb https://mirrors.ustc.edu.cn/debian/ bookworm main contrib non-free
deb https://mirrors.ustc.edu.cn/debian/ bookworm-updates main contrib non-free
SRC

# 屏蔽apt非稳定接口警告
export APT_LISTCHANGES_FRONTEND=none
export APT_GET_NO_LOCK_WARNING=1

apt update -y
# 精简软件：使用 vim-tiny 替代完整版 vim，大幅缩减体积
apt install -y systemd openssh-server net-tools iproute2 vim-tiny less

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

# 设置 root 密码
echo "root:123456" | chpasswd

# 深度清理缓存、无用文件
apt clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/locale/*
EOF

# 解除所有绑定挂载
sudo umount "${ROOTFS_DIR}/dev/pts"
sudo umount "${ROOTFS_DIR}/dev" "${ROOTFS_DIR}/proc" "${ROOTFS_DIR}/sys"

# 制作 256M ext4 镜像（文件名保留 rootfs_128m.ext4 适配原有分区名）
sudo dd if=/dev/zero of="${IMG_FILE}" bs=1M count=256
sudo mkfs.ext4 -F "${IMG_FILE}"

# 拷贝文件到镜像
sudo mount "${IMG_FILE}" "${MNT_DIR}"
sudo cp -a "${ROOTFS_DIR}"/* "${MNT_DIR}/"
sudo umount "${MNT_DIR}"

echo "====================================="
echo "  Debian 12 rootfs 构建完成"
echo "  镜像: ${IMG_FILE} (256M)"
echo "  账号: root  密码: 123456"
echo "====================================="
