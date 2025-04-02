#!/bin/bash

set -e -u -x

sudo apt update

# 不进行交互安装
export DEBIAN_FRONTEND=noninteractive
ARCH="loong64"
DISKIMG="deepin-$ARCH.img"
DISKSIZE="4096"
ROOTFS="rootfs"
dist_version="beige"
SOURCES_FILE=config/apt/sources.list
PACKAGES_FILE=config/packages.list/packages.list
readarray -t REPOS < $SOURCES_FILE
PACKAGES=`cat $PACKAGES_FILE | grep -v "^-" | xargs | sed -e 's/ /,/g'`

function run_command_in_chroot()
{
    rootfs="$1"
    command="$2"
    sudo chroot "$rootfs" /usr/bin/env bash -e -o pipefail -c "export DEBIAN_FRONTEND=noninteractive && $command"
}

# 需要安装以下环境
sudo apt install -y mmdebstrap qemu-user-static usrmerge usr-is-merged binfmt-support gdisk dosfstools
# 开启异架构支持
sudo systemctl start systemd-binfmt

# 生成 img
# 创建一个空白的镜像文件。
dd if=/dev/zero of=$DISKIMG bs=1M count=$DISKSIZE

# n # 新建分区
# p # 主分区
# 1 # 分区号为1
# # 接受默认的起始扇区
# +512M # 分区大小为512MB
# t # 更改分区类型
# ef00 # 设置为EFI系统分区（如果是传统的MBR和BIOS，则可能是83为主分区）
# w # 写入分区表并退出
# 非交互式执行fdisk
# sudo fdisk $DISKIMG << EOF
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

sudo gdisk $DISKIMG << EOF
n
1

+300M
ef00
n
2



w
y
EOF

# 找一个未被使用的循环（loop）设备，并绑定到 img 镜像，同时扫描并处理镜像所有分区
DEV=$(sudo losetup --partscan --find --show $DISKIMG)

# 分区创建完毕后，记得格式化新分区（此处假设是EFI系统分区，用fat32格式）
sudo mkfs.fat -F32 "${DEV}p1"
sudo fatlabel "${DEV}p1" efi
sudo mkfs.ext4 "${DEV}p2" # 根分区 (/)
sudo e2label "${DEV}p2" root

TMP="tmp"
mkdir -p $TMP

# 创建根文件系统
if [[ -z "$(ls -A $TMP)" ]];
then
    sudo mmdebstrap \
        --hook-dir=/usr/share/mmdebstrap/hooks/merged-usr \
        --include=$PACKAGES \
        --skip=check/empty \
        --components="main,commercial,community" \
        --architectures=$ARCH \
        $dist_version \
        $TMP \
        "${REPOS[@]}"

    sudo mount --bind /dev $TMP/dev
    sudo mount -t proc chproc $TMP/proc
    sudo mount -t sysfs chsys $TMP/sys
    sudo mount -t tmpfs -o "size=99%" tmpfs $TMP/tmp
    sudo mount -t tmpfs -o "size=99%" tmpfs $TMP/var/tmp
    sudo mount --bind /etc/resolv.conf $TMP/etc/resolv.conf

    run_command_in_chroot $TMP "
    useradd -mg users deepin && usermod -aG sudo deepin
    chsh -s /bin/bash deepin
    echo deepin:deepin | chpasswd
    "

    run_command_in_chroot $TMP "
    sed -i -E 's/#[[:space:]]?(en_US.UTF-8[[:space:]]+UTF-8)/\1/g' /etc/locale.gen
    sed -i -E 's/#[[:space:]]?(zh_CN.UTF-8[[:space:]]+UTF-8)/\1/g' /etc/locale.gen

    locale-gen
    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure locales
    "

    run_command_in_chroot $TMP "
    apt update && \
    apt install linux-image-deepin-hwe-loong64 && \
    grub-efi-loong64
    "

    sudo umount $TMP/sys
    sudo umount $TMP/proc
    sudo umount $TMP/dev/pts
    sudo umount $TMP/dev
    sudo umount $TMP/var/tmp
    sudo umount $TMP/tmp
fi

mkdir -p $ROOTFS
sudo mount "${DEV}p2" $ROOTFS
sudo cp -a $TMP/* $ROOTFS


sudo mkdir -p $ROOTFS/boot/efi
sudo mount "${DEV}p1" $ROOTFS/boot/efi
sudo cp -r config/efi/* $ROOTFS/boot/efi

sudo mount --bind /dev $ROOTFS/dev
sudo mount -t proc chproc $ROOTFS/proc
sudo mount -t sysfs chsys $ROOTFS/sys
sudo mount -t tmpfs -o "size=99%" tmpfs $ROOTFS/tmp
sudo mount -t tmpfs -o "size=99%" tmpfs $ROOTFS/var/tmp

root_uuid=$(sudo blkid -s UUID -o value "${DEV}p2")

sudo mkdir -p $ROOTFS/boot/grub
sudo cp -r config/grub/* $ROOTFS/boot/grub
sudo sed -i "s/root_uuid/$root_uuid/g" $ROOTFS/boot/efi/EFi/BOOT/grub.cfg
sudo cp $ROOTFS/boot/efi/EFi/boot/grub.cfg $ROOTFS/boot/efi/EFi/deepin/grub.cfg

run_command_in_chroot $ROOTFS "grub-install --target=loongarch64-efi --efi-directory=/boot/efi --recheck"

sudo tee $ROOTFS/etc/fstab << EOF
LABEL=efi  /boot/efi  vfat    defaults,x-systemd.automount          0       2
LABEL=root  /               ext4    defaults,rw,errors=remount-ro,x-systemd.growfs  0       1
EOF

# 设置中文
sudo tee $ROOTFS/etc/locale.conf << EOF
LANG=zh_CN.UTF-8
LANGUAGE=zh_CN
EOF

sudo echo "deepin-$ARCH" | sudo tee $ROOTFS/etc/hostname > /dev/null

run_command_in_chroot $ROOTFS "
apt clean
rm -rf /var/cache/apt/archives/*
"
# 手动操作
# update-initramfs -u -k all
# /usr/sbin/update-grub

sudo umount -l $ROOTFS
sudo losetup -D ${DEV}
