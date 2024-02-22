# 介绍

在 qemu 中运行 riscv 架构的系统。

## 准备 rootfs

执行脚本制作根文件系统

```bash
./build-img.sh
```

# 编译龙芯内核

```bash
git clone git@github.com:chenhuacai/linux.git -b loongarch-next
cd linux
# 配置内核
make ARCH=loongarch defconfig
make ARCH=loongarch scripts_basic
make ARCH=loongarch menuconfig

# 生成
make ARCH=loongarch -j $((`nproc`-1))
# 产物
arch/loongarch/boot/vmlinuz.efi
```

不过好像编译的内核有点问题，先用人家的 https://github.com/yangxiaojuan-loongson/qemu-binary，下载 vmlinuz.efi

# qemu 中启动

```bash
sudo qemu-system-loongarch64 -nographic -machine virt -m 4G \
    -bios bios/QEMU_EFI.fd \
    -kernel bios/vmlinuz-6.7.0-loong64-desktop \
    -object rng-random,filename=/dev/urandom,id=rng0 \
    -append "console=ttyS0 rw root=/dev/vda2" \
    -device virtio-blk-pci,drive=hd0 \
    -drive file=deepin-beige-loong64.img,format=qcow2,id=hd0,if=none \
    -serial mon:stdio \
    -net nic,model=virtio -net user,hostfwd=tcp::2222-:22 \
    -device nec-usb-xhci,id=xhci,addr=0x1b \
    -device usb-tablet,id=tablet,bus=xhci.0,port=1 \
    -device usb-kbd,id=keyboard,bus=xhci.0,port=2
```

在 virt-manager 配置内核启动

virt-manager 中不支持 loongarch, 后端使用 libvirtd 进行较验，需要对 libvirtd 进行修改。

# 制作系统到磁盘

```bash
./build-img.sh
```

手动操作

```bash
# 进入根文件系统
sudo chroot $ROOTFS bash
apt update && apt install linux-image-6.7.0-loong64-desktop
# 生成引导
/usr/sbin/update-grub

# 虚拟机制定 console=ttyS0 参数给内核
#/boot/efi/grub/grub.cfg 120行添加console=ttyS0
sed -i '120s/$/ console=ttyS0/' /boot/efi/grub/grub.cfg

# 物理设备还需要安装一个包
sudo apt install linux-firmware
```

## 编辑 grub

/boot/efi/EFI/boot/grub.cfg

```bash
root_uuid=`blkid | grep "/dev/nbd0p2" |  awk -F '="' '{print $2}' | awk -F '"' '{print $1}'`
tee -a /boot/efi/EFI/BOOT/grub.cfg <<-'EOF'
search.fs_uuid root_uuid root 
set prefix=($root)'/boot/grub'
configfile $prefix/grub.cfg
EOF
sed -i "s/root_uuid/$root_uuid/g" /boot/efi/EFi/BOOT/grub.cfg
cp /boot/efi/EFi/boot/grub.cfg /boot/efi/EFi/deepin/grub.cfg

#sed -i "113s/gnulinux-simple/gnulinux-simple-$root_uuid/" /boot/efi/grub/grub.cfg
```

/dev/nbd0p2 是根分区所在设备

## 编辑分区表

```bash
# 自动生成
sudo apt install arch-install-scripts
sudo su -
genfstab -U $ROOTFS > $ROOTFS/etc/fstab

# 设置分区标签
e2label /dev/nbd0p2 root
```

## 卸载

```bash
sudo umount $ROOTFS/dev
sudo umount $ROOTFS/proc
sudo umount $ROOTFS/sys
sudo umount $ROOTFS/boot/efi
sudo umount $ROOTFS
DEV=/dev/nbd0
sudo qemu-nbd -d $DEV
```

## 启动系统

```bash
sudo qemu-system-loongarch64 -nographic -machine virt -m 4G \
    -bios bios/QEMU_EFI.fd \
    -device virtio-blk-pci,drive=hd0 \
    -drive file=deepin-beige-loong64.img,format=qcow2,id=hd0,if=none \
    -boot order=c \
    -net nic,model=virtio -net user,hostfwd=tcp::2222-:22 \
    -serial mon:stdio \
    -device virtio-gpu-pci \
    -display gtk
```

# 参考

[在 libvirt 中运行 RISC-V 虚拟机](https://jia.je/software/2022/05/31/qemu-rv64-in-libvirt/)

[deepin V23 Beta3 Loongarch](https://cdimage.uniontech.com/community/Loongarch/test-20240205-loong64/README.pdf)
