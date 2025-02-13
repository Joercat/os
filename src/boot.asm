section .text
global _start
extern kernel_main

_start:
    mov rsp, stack_top
    cli
    call setup_long_mode
    call kernel_main
    hlt

setup_long_mode:
    mov rax, cr4
    or rax, (1 << 5)
    mov cr4, rax
    
    mov rax, page_table_l4
    mov cr3, rax
    
    mov rcx, 0xC0000080
    rdmsr
    or rax, (1 << 8)
    wrmsr
    
    mov rax, cr0
    or rax, (1 << 31)
    mov cr0, rax
    ret

section .bss
align 4096
stack_bottom:
    resb 16384
stack_top:

align 4096
page_table_l4:
    resb 4096
page_table_l3:
    resb 4096
page_table_l2:
    resb 4096
page_table_l1:
    resb 4096
