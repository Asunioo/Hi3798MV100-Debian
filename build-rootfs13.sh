#!/bin/bash
set -euo pipefail

WORK_DIR="$GITHUB_WORKSPACE/build"
ROOTFS_DIR="${WORK_DIR}/rootfs"
# 【修改点1】镜像文件名更改为 rootfs.img
IMG_FILE="${WORK_DIR}/rootfs.img"
MNT_DIR="${WORK_DIR}/mnt"

# 清理旧文件
rm -rf "${WORK_DIR}"
mkdir -p "${ROOTFS_DIR}" "${MNT_DIR}"

# 安装依赖
sudo apt update -y
sudo apt install -y debootstrap qemu-user-static binfmt-support e2fsprogs

# 【修改点2】拉取 Debian 13 Trixie armhf，使用华为源 https 协议
sudo debootstrap --arch=armhf trixie "${ROOTFS_DIR}" https://repo.huaweicloud.com/debian/

# 注入 qemu
sudo cp /usr/bin/qemu-arm-static "${ROOTFS_DIR}/usr/bin/"

# 绑定基础目录 + 新增 pts 解决终端/日志报错
sudo mount --bind /dev "${ROOTFS_DIR}/dev"
sudo mount --bind /proc "${ROOTFS_DIR}/proc"
sudo mount --bind /sys "${ROOTFS_DIR}/sys"
sudo mount --bind /dev/pts "${ROOTFS_DIR}/dev/pts"

# ===================== 新增：拷贝Overlay配置 =====================
echo ">>> 拷贝系统预置配置(网络/MAC)"
sudo cp -r "${GITHUB_WORKSPACE}/overlay"/* "${ROOTFS_DIR}/" || true
sudo chmod 644 "${ROOTFS_DIR}/etc/network/interfaces"
# =================================================================

# Chroot 配置系统
sudo chroot "${ROOTFS_DIR}" << EOF
# 【修改点3】修复软件源：将 USTC 替换为华为源 (https)，Debian 13 Trixie
cat > /etc/apt/sources.list << SRC
deb https://repo.huaweicloud.com/debian/ trixie main contrib non-free non-free-firmware
deb https://repo.huaweicloud.com/debian/ trixie-updates main contrib non-free non-free-firmware
# 华为源同样包含安全更新目录
deb https://repo.huaweicloud.com/debian/ trixie-security main contrib non-free non-free-firmware
SRC

# 屏蔽apt非稳定接口警告
export APT_LISTCHANGES_FRONTEND=none
export APT_GET_NO_LOCK_WARNING=1

apt update -y

# ===================== 【改动1】扩展基础工具包 + 时间同步组件 =====================
# 新增 systemd-timesyncd 实现开机自动校时
apt install -y \
systemd openssh-server net-tools iproute2 vim less \
curl wget dnsutils lsof rsync tree unzip zip xz-utils procps \
systemd-timesyncd

# ===================== 【改动2】设置中国时区 Asia/Shanghai（无交互） =====================
export TZ=Asia/Shanghai
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
echo "Asia/Shanghai" > /etc/timezone
dpkg-reconfigure -f noninteractive tzdata

# ========== 新增：配置开机自动同步系统时间 ==========
# 修改timesyncd配置，使用国内NTP服务器
cat > /etc/systemd/timesyncd.conf << NTPCFG
[Time]
NTP=ntp.aliyun.com ntp1.aliyun.com cn.ntp.org.cn
FallbackNTP=0.debian.pool.ntp.org
NTPCFG
# 启用时间同步服务开机自启
systemctl enable systemd-timesyncd.service
# 启用系统时钟同步写入硬件RTC
echo "HWCLOCKACCESS=yes" >> /etc/default/hwclock

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

# 启用传统网络服务开机自启
systemctl enable networking

# 深度清理缓存、无用文件
apt clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/locale/*
EOF

# 解除所有绑定挂载
sudo umount "${ROOTFS_DIR}/dev/pts"
sudo umount "${ROOTFS_DIR}/dev" "${ROOTFS_DIR}/proc" "${ROOTFS_DIR}/sys"

# =====================【镜像大小修改】由256M改为384M，需要更大就改count数值 =====================
# count=384 →384MB，count=512→512MB
sudo dd if=/dev/zero of="${IMG_FILE}" bs=1M count=512
sudo mkfs.ext4 -F "${IMG_FILE}"

# 拷贝文件到镜像
sudo mount "${IMG_FILE}" "${MNT_DIR}"
sudo cp -a "${ROOTFS_DIR}"/* "${MNT_DIR}/"
sudo umount "${MNT_DIR}"

echo "====================================="
# 【修改点4】更新输出信息为 Debian 13
echo "  Debian 13 rootfs 构建完成"
echo "  镜像: ${IMG_FILE} (512M)"
echo "  账号: root  密码: 123456"
echo "  网卡: eth0 自动DHCP  MAC: BC:25:E0:3F:F1:D9"
echo "  已开启开机自动NTP时间同步(阿里云NTP)"
echo "====================================="
