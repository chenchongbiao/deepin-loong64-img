#!/bin/bash

# 何命令失败（退出状态非0），则脚本会终止执行
set -o errexit
# 尝试使用未设置值的变量，脚本将停止执行
set -o nounset

ROOTFS=`mktemp -d`
TARGET_DEVICE="qemu"
TARGET_ARCH="loong64"
DIST_VERSION="beige"
DISKSIZE="60G"
DISKIMG="deepin-$TARGET_DEVICE-$TARGET_ARCH.qcow2"
readarray -t REPOS < ./profiles/sources.list
PACKAGES=`cat ./profiles/packages.txt | grep -v "^-" | xargs | sed -e 's/ /,/g'`

sudo apt update -y
sudo apt-get install -y qemu-user-static binfmt-support mmdebstrap arch-test usrmerge usr-is-merged qemu-system-misc systemd-container

# sudo mmdebstrap --arch=$TARGET_ARCH --variant=buildd \
#         --hook-dir=/usr/share/mmdebstrap/hooks/merged-usr \
#         --include=$PACKAGES \
#         --customize=./profiles/stage2.sh \
#         beige $ROOTFS\
#         "${REPOS[@]}"
sudo mmdebstrap \
        --hook-dir=/usr/share/mmdebstrap/hooks/merged-usr \
        --include=$PACKAGES \
        --components="main,commercial,community" \
        --architectures=$TARGET_ARCH \
        --customize=./config/hooks.chroot/second-stage \
        $DIST_VERSION \
        $ROOTFS \
        "${REPOS[@]}"

sudo echo "deepin-$TARGET_ARCH-$TARGET_DEVICE" | sudo tee $ROOTFS/etc/hostname > /dev/null
sudo echo "Asia/Shanghai" | sudo tee $ROOTFS/etc/timezone > /dev/null
sudo ln -sf /usr/share/zoneinfo/Asia/Shanghai $ROOTFS/etc/localtime

# sudo virt-make-fs --partition=gpt --type=ext4 --size=+10G --format=qcow2 $ROOTFS $DISKIMG
# -l 懒卸载，避免有程序使用 ROOTFS 还没退出
# sudo umount -l $ROOTFS
# sudo rm -rf $ROOTFS