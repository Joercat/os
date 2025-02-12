section .text
global _start
extern kernel_main

_start:
    ; Set up stack
    mov rsp, stack_top
    
    ; Clear interrupts during init
    cli
    
    ; Initialize essential CPU state
    call setup_long_mode
    call setup_paging
    
    ; Jump to kernel
    call kernel_main
    
    ; Should never return, but halt if it does
    hlt

setup_long_mode:
    ; Enable PAE
    mov eax, cr4
    or eax, 1 << 5
    mov cr4, eax
    
    ; Set long mode bit
    mov ecx, 0xC0000080
    rdmsr
    or eax, 1 << 8
    wrmsr
    ret

section .bss
align 4096
stack_bottom:
    resb 16384  ; 16 KB stack
stack_top:
