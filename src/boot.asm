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
    
    ; Jump to kernel
    call kernel_main
    
    ; Should never return, but halt if it does
    hlt

setup_long_mode:
    ; Enable PAE
    mov rax, cr4
    or rax, (1 << 5)
    mov cr4, rax
    
    ; Set up page tables
    mov rax, page_table_l4
    mov cr3, rax
    
    ; Enable long mode
    mov rcx, 0xC0000080
    rdmsr
    or rax, (1 << 8)
    wrmsr
    
    ; Enable paging
    mov rax, cr0
    or rax, (1 << 31)
    mov cr0, rax
    ret

section .bss
align 4096
stack_bottom:
    resb 16384  ; 16 KB stack
stack_top:

; Page tables
align 4096
page_table_l4:
    resb 4096
page_table_l3:
    resb 4096
page_table_l2:
    resb 4096
page_table_l1:
    resb 4096
; if your reading this suck my cock
