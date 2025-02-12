# Multi-stage build for optimal size
FROM gcc:latest as builder

WORKDIR /app
COPY . .

# Install NASM assembler
RUN apt-get update && apt-get install -y nasm

# Compile assembly
RUN nasm -f elf64 boot.asm -o boot.o

# Compile C file
RUN gcc -c hardware.c -o hardware.o

# Compile C++ and link everything
RUN g++ main.cpp boot.o hardware.o -o phone_os

# Final stage
FROM debian:bullseye-slim

WORKDIR /app
COPY --from=builder /app/phone_os .

# Expose port for remote management
EXPOSE 8080

# Run the OS
CMD ["./phone_os"]
