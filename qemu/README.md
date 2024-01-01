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
    -bios /media/bluesky/inst_231/qemu/bios/QEMU_loong64_EFI.fd \
    -kernel /media/bluesky/inst_231/qemu/kernel/vmlinuz.efi \
    -object rng-random,filename=/dev/urandom,id=rng0 \
    -append "console=ttyS0 rw root=/dev/vda1" \
    -device virtio-blk-pci,drive=hd0 \
    -device virtio-net-pci,netdev=usernet \
    -drive file=deepin-qemu-loong64.qcow2,format=qcow2,id=hd0,if=none \
    -net nic,model=virtio \
    -netdev user,id=usernet,hostfwd=tcp::2222-:22
```

在 virt-manager 配置内核启动

virt-manager 中不支持 loongarch, 后端使用 libvirtd 进行较验，需要对 libvirtd 进行修改。

# 参考

[在 libvirt 中运行 RISC-V 虚拟机](https://jia.je/software/2022/05/31/qemu-rv64-in-libvirt/)
