section .text
global _start
extern main

_start:
    call init_platform
    call main
    
init_platform:
    push ebp
    mov ebp, esp
    ; Platform initialization code
    pop ebp
    ret
