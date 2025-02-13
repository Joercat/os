# Build environment
FROM gcc:latest as builder

WORKDIR /os
COPY . .

# Install required tools
RUN apt-get update && \
    apt-get install -y nasm

# Create include directory and compile
RUN mkdir -p include && \
    nasm -f elf64 boot.asm -o boot.o && \
    g++ -c -ffreestanding -fno-exceptions -fno-rtti -I./include kernel.cpp -o kernel.o && \
    ld -T linker.ld -o phone_os boot.o kernel.o

# Runtime environment
FROM debian:bullseye-slim

WORKDIR /os
COPY --from=builder /os/phone_os .

EXPOSE 8080

CMD ["./phone_os"]
