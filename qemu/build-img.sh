#!/bin/bash

set -e -u -x

sudo apt update

# 不进行交互安装
export DEBIAN_FRONTEND=noninteractive
ARCH="loong64"
DISKIMG="deepin-beige-$ARCH.img"
IMGSIZE="60G"
ROOTFS=`mktemp -d`
dist_version="beige"
dist_name="deepin"
SOURCES_FILE=config/apt/sources.list
PACKAGES_FILE=config/packages.list/packages.list
readarray -t REPOS < $SOURCES_FILE
PACKAGES=`cat $PACKAGES_FILE | grep -v "^-" | xargs | sed -e 's/ /,/g'`

sudo apt update -y && sudo apt install -y curl git mmdebstrap usrmerge systemd-container

DEV="/dev/nbd0"
# 加载 nbd 模块，允许创建的最大分区数为16
sudo modprobe nbd max_part=16
sudo qemu-nbd -d $DEV
rm $DISKIMG || true

qemu-img create -f qcow2 -o size=$IMGSIZE $DISKIMG
# QEMU 镜像文件连接到一个 NBD 设备
sudo qemu-nbd -c $DEV $DISKIMG

# n # 新建分区
# p # 主分区
# 1 # 分区号为1
# # 接受默认的起始扇区
# +512M # 分区大小为512MB
# t # 更改分区类型
# ef00 # 设置为EFI系统分区（如果是传统的MBR和BIOS，则可能是83为主分区）
# w # 写入分区表并退出
# 非交互式执行fdisk
# sudo fdisk $DEV << EOF
# n
# p
# 1

# +300M
# t
# ef00
# n
# p
# 2


# w
# EOF

sudo gdisk $DEV << EOF
n
1

+300M
ef00
n
2



w
y
EOF

# 分区创建完毕后，记得格式化新分区（此处假设是EFI系统分区，用fat32格式）
sudo mkfs.fat -F32 "${DEV}p1"
sudo mkfs.ext4 "${DEV}p2" # 根分区 (/)

sudo mount "${DEV}p2" $ROOTFS
# sudo rm -rf $ROOTFS/lost+found

sudo mmdebstrap \
    --hook-dir=/usr/share/mmdebstrap/hooks/merged-usr \
    --include=$PACKAGES \
    --skip=check/empty \
    --components="main,commercial,community" \
    --architectures=$ARCH \
    --customize=./config/hooks.chroot/second-stage \
    $dist_version \
    $ROOTFS \
    "${REPOS[@]}"

sudo echo "deepin-$ARCH" | sudo tee $ROOTFS/etc/hostname > /dev/null

sudo mount --bind /dev $ROOTFS/dev
sudo mount -t proc none $ROOTFS/proc
sudo mount -t sysfs none $ROOTFS/sys

sudo mkdir -p $ROOTFS/boot/efi
sudo mount "${DEV}p1" $ROOTFS/boot/efi
sudo cp -r config/efi/* $ROOTFS/boot/efi

sudo mkdir -p $ROOTFS/boot/grub

# 手动操作
# update-initramfs -u -k all
# /usr/sbin/update-grub

# sudo umount $ROOTFS/dev
# sudo umount $ROOTFS/proc
# sudo umount $ROOTFS/sys

# sudo umount $ROOTFS/boot/efi
# sudo umount $ROOTFS

# 执行完操作后，断开
# sudo qemu-nbd -d $DEV
