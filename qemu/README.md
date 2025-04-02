# 介绍

在 qemu 中运行 loong64 架构的系统。

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

# 制作系统到磁盘

```bash
./build-img.sh
```

手动操作

```bash
# 物理设备还需要安装一个固件包
sudo apt install linux-firmware
```

## 启动系统

```bash
qemu-system-loong64 -machine virt -m 4G \
    -bios bios/QEMU_EFI.fd \
    -device virtio-blk-pci,drive=hd0 \
    -drive file=deepin-loong64.img,format=raw,id=hd0,if=none \
    -boot order=c \
    -net nic,model=virtio -net user,hostfwd=tcp::2222-:22 \
    -device virtio-gpu-pci \
    -device usb-ehci,id=usb-bus \
    -device usb-kbd \
    -display gtk
```

# 参考

[在 libvirt 中运行 RISC-V 虚拟机](https://jia.je/software/2022/05/31/qemu-rv64-in-libvirt/)

[deepin V23 Beta3 Loongarch](https://cdimage.uniontech.com/community/Loongarch/test-20240205-loong64/README.pdf)
