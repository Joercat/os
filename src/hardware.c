#include <stdint.h>

// Function declarations
uint64_t* get_page_directory(void);
void load_idt(void);
void setup_pic(void);
void enable_interrupts(void);
void handle_hardware_interrupts(void);
void handle_software_interrupts(void);
void map_kernel_space(uint64_t* pml4);

// Memory management
uint64_t* get_page_directory(void) {
    static uint64_t page_dir[512] __attribute__((aligned(4096)));
    for(int i = 0; i < 512; i++) {
        page_dir[i] = (i * 0x200000) | 0x83;  // Present + RW + Huge
    }
    return page_dir;
}

void map_kernel_space(uint64_t* pml4) {
    uint64_t* pdpt = (uint64_t*)(pml4[0] & ~0xFFF);
    uint64_t* pd = (uint64_t*)(pdpt[0] & ~0xFFF);
    
    // Map first 1GB for kernel
    for(int i = 0; i < 512; i++) {
        pd[i] = (i * 0x200000) | 0x83;
    }
}

// Interrupt handling
void load_idt(void) {
    struct IDTEntry {
        uint16_t offset_low;
        uint16_t selector;
        uint8_t ist;
        uint8_t type_attr;
        uint16_t offset_mid;
        uint32_t offset_high;
        uint32_t zero;
    } __attribute__((packed));

    static struct IDTEntry idt[256] __attribute__((aligned(8)));
    
    // Set up default handlers
    for(int i = 0; i < 256; i++) {
        idt[i].selector = 0x08;
        idt[i].type_attr = 0x8E;
        idt[i].ist = 0;
        idt[i].zero = 0;
    }

    struct {
        uint16_t limit;
        uint64_t base;
    } __attribute__((packed)) IDTR = {
        .limit = sizeof(idt) - 1,
        .base = (uint64_t)idt,
    };
    
    asm volatile("lidt %0" : : "m"(IDTR));
}

void setup_pic(void) {
    // ICW1
    outb(0x20, 0x11);
    outb(0xA0, 0x11);
    
    // ICW2
    outb(0x21, 0x20);  // Master PIC vector offset
    outb(0xA1, 0x28);  // Slave PIC vector offset
    
    // ICW3
    outb(0x21, 0x04);  // Tell Master PIC about Slave
    outb(0xA1, 0x02);  // Tell Slave PIC its cascade identity
    
    // ICW4
    outb(0x21, 0x01);
    outb(0xA1, 0x01);
    
    // OCW1 - Enable all interrupts
    outb(0x21, 0x0);
    outb(0xA1, 0x0);
}

void enable_interrupts(void) {
    asm volatile("sti");
}

void handle_hardware_interrupts(void) {
    uint8_t irq = check_interrupt_status();
    if(irq) {
        switch(irq) {
            case 1:  // Keyboard
                handle_keyboard();
                break;
            case 12: // Mouse
                handle_mouse();
                break;
            default:
                send_eoi(irq);
        }
    }
}

void handle_software_interrupts(void) {
    uint32_t syscall_num = get_syscall_number();
    switch(syscall_num) {
        case 0:  // read
            sys_read();
            break;
        case 1:  // write
            sys_write();
            break;
        case 2:  // open
            sys_open();
            break;
    }
}

// Helper functions
static inline void outb(uint16_t port, uint8_t val) {
    asm volatile("outb %0, %1" : : "a"(val), "Nd"(port));
}

static uint8_t check_interrupt_status(void) {
    return inb(0x20);  // Read Master PIC IRR
}

static inline uint8_t inb(uint16_t port) {
    uint8_t ret;
    asm volatile("inb %1, %0" : "=a"(ret) : "Nd"(port));
    return ret;
}

static void send_eoi(uint8_t irq) {
    if(irq >= 8)
        outb(0xA0, 0x20);  // Slave PIC EOI
    outb(0x20, 0x20);      // Master PIC EOI
}

static void handle_keyboard(void) {
    uint8_t scancode = inb(0x60);
    process_keypress(scancode);
    send_eoi(1);
}

static void handle_mouse(void) {
    uint8_t mouse_data = inb(0x60);
    process_mouse_movement(mouse_data);
    send_eoi(12);
}

static void process_keypress(uint8_t scancode) {
    // Update keyboard buffer
    keyboard_buffer[keyboard_index++] = scancode;
    if(keyboard_index >= KEYBOARD_BUFFER_SIZE)
        keyboard_index = 0;
}

static void process_mouse_movement(uint8_t data) {
    // Update mouse position
    mouse_x += (data & 0x10) ? data - 256 : data;
    if(mouse_x < 0) mouse_x = 0;
    if(mouse_x >= SCREEN_WIDTH) mouse_x = SCREEN_WIDTH - 1;
}

static uint32_t get_syscall_number(void) {
    uint32_t num;
    asm volatile("mov %%eax, %0" : "=r"(num));
    return num;
}

static void sys_read(void) {
    // Implement read syscall
    handle_read_request();
}

static void sys_write(void) {
    // Implement write syscall
    handle_write_request();
}

static void sys_open(void) {
    // Implement open syscall
    handle_open_request();
}
// suck my pp
