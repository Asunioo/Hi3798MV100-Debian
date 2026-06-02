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

# 拉取 Debian 12 Bookworm armhf
sudo debootstrap --arch=armhf bookworm "${ROOTFS_DIR}" https://mirrors.ustc.edu.cn/debian/

# 注入 qemu
sudo cp /usr/bin/qemu-arm-static "${ROOTFS_DIR}/usr/bin/"

# 绑定基础目录 + pts
sudo mount --bind /dev "${ROOTFS_DIR}/dev"
sudo mount --bind /proc "${ROOTFS_DIR}/proc"
sudo mount --bind /sys "${ROOTFS_DIR}/sys"
sudo mount --bind /dev/pts "${ROOTFS_DIR}/dev/pts"

# 拷贝Overlay配置
echo ">>> 拷贝系统预置配置(网络/MAC)"
sudo cp -r "${GITHUB_WORKSPACE}/overlay"/* "${ROOTFS_DIR}/" || true
sudo chmod 644 "${ROOTFS_DIR}/etc/network/interfaces"

# Chroot 配置系统
sudo chroot "${ROOTFS_DIR}" << EOF
# 软件源
cat > /etc/apt/sources.list << SRC
deb https://mirrors.ustc.edu.cn/debian/ bookworm main contrib non-free
deb https://mirrors.ustc.edu.cn/debian/ bookworm-updates main contrib non-free
SRC

export APT_LISTCHANGES_FRONTEND=none
export APT_GET_NO_LOCK_WARNING=1
apt update -y

# 安装工具+时间同步+扩容依赖
apt install -y \
systemd openssh-server net-tools iproute2 vim less \
curl wget dnsutils lsof rsync tree unzip zip xz-utils procps \
systemd-timesyncd parted e2fsprogs

# 时区
export TZ=Asia/Shanghai
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
echo "Asia/Shanghai" > /etc/timezone
dpkg-reconfigure -f noninteractive tzdata

# NTP时间同步
cat > /etc/systemd/timesyncd.conf << NTPCFG
[Time]
NTP=ntp.aliyun.com ntp1.aliyun.com cn.ntp.org.cn
FallbackNTP=0.debian.pool.ntp.org
NTPCFG
systemctl enable systemd-timesyncd.service
echo "HWCLOCKACCESS=yes" >> /etc/default/hwclock

# 串口ttyAMA0
echo "ttyAMA0" >> /etc/securetty
systemctl enable getty@ttyAMA0.service

# SSH允许root登录
sed -i 's/^#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
systemctl enable ssh

# 主机名DNS
echo "hi3798mv100" > /etc/hostname
echo "127.0.0.1   localhost hi3798mv100" > /etc/hosts
echo "nameserver 114.114.114.114" > /etc/resolv.conf

# 清理海纳思残留
rm -f /etc/nasversion
rm -rf /usr/local/bin/histb* /etc/init.d/histb*

# root密码
echo "root:123456" | chpasswd
systemctl enable networking

# ============【关键：开机自动扩容脚本】============
# 写入扩容脚本，只首次开机执行一次resize
cat > /usr/bin/auto_resize_root.sh << RESIZE
#!/bin/bash
PART=/dev/mmcblk0p9
FLAG=/etc/.resize_done
if [ ! -f \${FLAG} ];then
    echo "Start resize2fs \${PART}"
    resize2fs \${PART}
    touch \${FLAG}
    echo "Resize finish"
fi
RESIZE
chmod +x /usr/bin/auto_resize_root.sh

# systemd开机服务，挂载后执行扩容
cat > /etc/systemd/system/auto-resize-root.service << SRV
[Unit]
Description=Auto Resize rootfs mmcblk0p9
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/bin/auto_resize_root.sh

[Install]
WantedBy=multi-user.target
SRV
systemctl enable auto-resize-root.service
# ==================================================

# 系统瘦身清理
apt clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/locale/*
EOF

# 取消绑定挂载
sudo umount "${ROOTFS_DIR}/dev/pts"
sudo umount "${ROOTFS_DIR}/dev" "${ROOTFS_DIR}/proc" "${ROOTFS_DIR}/sys"

# 生成512M镜像
sudo dd if=/dev/zero of="${IMG_FILE}" bs=1M count=512
sudo mkfs.ext4 -F "${IMG_FILE}"

sudo mount "${IMG_FILE}" "${MNT_DIR}"
sudo cp -a "${ROOTFS_DIR}"/* "${MNT_DIR}/"
sudo umount "${MNT_DIR}"

echo "====================================="
echo "  Debian 12 rootfs 构建完成"
echo "  镜像: ${IMG_FILE} (512M)"
echo "  账号: root  密码: 123456"
echo "  网卡: eth0 自动DHCP  MAC: BC:25:E0:3F:F1:D9"
echo "  开机自动NTP校时 + 首次开机自动扩容mmcblk0p9到整分区3.1G"
echo "====================================="
