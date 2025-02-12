# Build environment
FROM gcc:latest as builder

WORKDIR /os
COPY . .

# Install required tools
RUN apt-get update && \
    apt-get install -y nasm xorriso grub-pc-bin grub-common

# Compile assembly bootloader
RUN nasm -f elf64 boot.asm -o boot.o

# Compile hardware interface
RUN gcc -c -ffreestanding -fno-stack-protector -fno-pie hardware.c -o hardware.o

# Compile kernel and link everything
RUN g++ -c -ffreestanding -fno-exceptions -fno-rtti -fno-pie main.cpp -o kernel.o && \
    ld -T linker.ld -o phone_os boot.o hardware.o kernel.o

# Create bootable image
RUN mkdir -p iso/boot/grub && \
    cp phone_os iso/boot/ && \
    echo 'set timeout=0' > iso/boot/grub/grub.cfg && \
    echo 'set default=0' >> iso/boot/grub/grub.cfg && \
    echo 'menuentry "PhoneOS" {' >> iso/boot/grub/grub.cfg && \
    echo '  multiboot /boot/phone_os' >> iso/boot/grub/grub.cfg && \
    echo '}' >> iso/boot/grub/grub.cfg && \
    grub-mkrescue -o phone_os.iso iso

# Runtime environment
FROM debian:bullseye-slim

WORKDIR /os
COPY --from=builder /os/phone_os.iso .
COPY --from=builder /os/phone_os .

EXPOSE 8080

CMD ["./phone_os"]
