section .text
global _start
extern main

_start:
    call init_platform
    call main
    
init_platform:
    push rbp
    mov rbp, rsp
    ; 64-bit platform initialization
    pop rbp
    ret
