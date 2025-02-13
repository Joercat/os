FROM gcc:latest as builder

WORKDIR /os
COPY . .

# Install required tools
RUN apt-get update && \
    apt-get install -y nasm

# Build steps separated for clarity
RUN mkdir -p include
RUN nasm -f elf64 boot.asm -o boot.o
RUN g++ -c -ffreestanding -fno-exceptions -fno-rtti -I./include kernel.cpp -o kernel.o
RUN ld -T linker.ld -o phone_os boot.o kernel.o

FROM debian:bullseye-slim
WORKDIR /os
COPY --from=builder /os/phone_os .
EXPOSE 8080
CMD ["./phone_os"]
