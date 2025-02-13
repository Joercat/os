#include <stdint.h>

class PhoneOS {
private:
    // Hardware constants
    static constexpr uint16_t VGA_WIDTH = 80;
    static constexpr uint16_t VGA_HEIGHT = 25;
    static constexpr uint16_t MAX_TASKS = 64;
    static constexpr uint64_t PAGE_SIZE = 4096;
    
    // Memory management
    volatile uint16_t* const video_memory = (uint16_t*)0xB8000;
    uint64_t* const page_directory = (uint64_t*)0x1000;
    uint16_t cursor_x = 0;
    uint16_t cursor_y = 0;
    
    // Interrupt handling
    struct IDTEntry {
        uint16_t offset_low;
        uint16_t selector;
        uint8_t ist;
        uint8_t type_attr;
        uint16_t offset_mid;
        uint32_t offset_high;
        uint32_t zero;
    } __attribute__((packed));

    alignas(8) IDTEntry idt[256];
    
    // Task management
    struct Task {
        uint64_t rsp;
        uint64_t cr3;
        bool active;
        uint8_t priority;
        uint32_t time_slice;
    };
    
    alignas(16) Task tasks[MAX_TASKS];
    uint32_t current_task = 0;
    uint32_t task_count = 0;
    
    // Memory protection
    struct MemoryRegion {
        uint64_t start;
        uint64_t size;
        uint32_t permissions;
    };
    
    MemoryRegion protected_regions[16];
    uint32_t region_count = 0;

public:
    void init() {
        // Initial memory setup
        volatile uint8_t* kernel_space = (uint8_t*)0x0;
        for(uint32_t i = 0; i < 0x1000000; i++) {
            kernel_space[i] = 0;
        }

        // Set up identity mapping for first 4GB
        uint64_t* pml4 = (uint64_t*)0x1000;
        uint64_t* pdpt = (uint64_t*)0x2000;
        uint64_t* pd = (uint64_t*)0x3000;

        pml4[0] = (uint64_t)pdpt | 0x3;
        pdpt[0] = (uint64_t)pd | 0x3;
        
        for(uint32_t i = 0; i < 512; i++) {
            pd[i] = (i * 0x200000) | 0x83;  // 2MB pages
        }

        // Set CR3 to point to our page tables
        asm volatile("mov %0, %%cr3" : : "r"(pml4) : "memory");
        
        // Disable interrupts during setup
        asm volatile("cli");

        // Initialize memory protection
        for(uint32_t i = 0; i < 16; i++) {
            protected_regions[i] = {0, 0, 0};
        }
        protected_regions[0] = {0x0, PAGE_SIZE * 1024, 0x3};
        region_count = 1;

        // Set up IDT
        for(uint32_t i = 0; i < 256; i++) {
            idt[i].selector = 0x08;
            idt[i].type_attr = 0x8E;
            idt[i].ist = 0;
            idt[i].zero = 0;
        }

        // Load IDT
        struct IDTR {
            uint16_t limit;
            uint64_t base;
        } __attribute__((packed)) idtr = {
            static_cast<uint16_t>(sizeof(idt) - 1),
            reinterpret_cast<uint64_t>(idt)
        };
        asm volatile("lidt %0" : : "m"(idtr) : "memory");

        // Configure PIC
        outb(0x20, 0x11);
        outb(0xA0, 0x11);
        outb(0x21, 0x20);
        outb(0xA1, 0x28);
        outb(0x21, 0x04);
        outb(0xA1, 0x02);
        outb(0x21, 0x01);
        outb(0xA1, 0x01);
        outb(0x21, 0x0);
        outb(0xA1, 0x0);

        // Initialize video memory
        for(uint32_t i = 0; i < VGA_WIDTH * VGA_HEIGHT; i++) {
            video_memory[i] = 0x0F20;
        }
        cursor_x = 0;
        cursor_y = 0;

        // Initialize task system
        for(uint32_t i = 0; i < MAX_TASKS; i++) {
            tasks[i].active = false;
            tasks[i].priority = 0;
            tasks[i].time_slice = 100;
            tasks[i].rsp = 0;
            tasks[i].cr3 = 0;
        }
        task_count = 0;
        current_task = 0;

        // Set up system timer
        outb(0x43, 0x36);
        uint16_t count = 1193180 / 100;  // 100 Hz
        outb(0x40, count & 0xFF);
        outb(0x40, count >> 8);

        // Enable interrupts
        asm volatile("sti");
    }

    
    void configure_pic() {
        // ICW1
        outb(0x20, 0x11);
        outb(0xA0, 0x11);
        
        // ICW2
        outb(0x21, 0x20);
        outb(0xA1, 0x28);
        
        // ICW3
        outb(0x21, 0x04);
        outb(0xA1, 0x02);
        
        // ICW4
        outb(0x21, 0x01);
        outb(0xA1, 0x01);
        
        // OCW1
        outb(0x21, 0x0);
        outb(0xA1, 0x0);
    }
    
    void init_video() {
        for(uint32_t i = 0; i < VGA_WIDTH * VGA_HEIGHT; i++) {
            video_memory[i] = 0x0F20;
        }
        cursor_x = 0;
        cursor_y = 0;
    }
    
    void init_task_manager() {
        for(uint32_t i = 0; i < MAX_TASKS; i++) {
            tasks[i].active = false;
            tasks[i].priority = 0;
            tasks[i].time_slice = 100;
        }
        task_count = 0;
        current_task = 0;
    }
    
    void process_interrupts() {
        uint8_t irq = check_interrupts();
        if(irq) {
            handle_interrupt(irq);
        }
    }
    
    uint8_t check_interrupts() {
        return inb(0x20);
    }
    
    void handle_interrupt(uint8_t irq) {
        switch(irq) {
            case 1:  // Keyboard
                handle_keyboard();
                break;
            case 8:  // Timer
                handle_timer();
                break;
            default:
                send_eoi(irq);
                break;
        }
    }
    
    void schedule_tasks() {
        if(task_count == 0) return;
        
        uint32_t next_task = find_next_task();
        if(next_task != current_task) {
            switch_task(next_task);
        }
    }
    
    uint32_t find_next_task() {
        uint32_t highest_priority = 0;
        uint32_t selected_task = current_task;
        
        for(uint32_t i = 0; i < MAX_TASKS; i++) {
            if(tasks[i].active && tasks[i].priority > highest_priority) {
                highest_priority = tasks[i].priority;
                selected_task = i;
            }
        }
        
        return selected_task;
    }
    
    void switch_task(uint32_t new_task) {
        Task& old_task = tasks[current_task];
        Task& new_task_obj = tasks[new_task];
        
        // Save current context
        asm volatile("mov %%rsp, %0" : "=r"(old_task.rsp));
        asm volatile("mov %%cr3, %0" : "=r"(old_task.cr3));
        
        // Load new context
        asm volatile("mov %0, %%cr3" : : "r"(new_task_obj.cr3));
        asm volatile("mov %0, %%rsp" : : "r"(new_task_obj.rsp));
        
        current_task = new_task;
    }
    
    void update_display() {
        refresh_screen();
        update_cursor();
    }
    
    void refresh_screen() {
        // Only update changed portions
        static uint16_t buffer[VGA_WIDTH * VGA_HEIGHT];
        for(uint32_t i = 0; i < VGA_WIDTH * VGA_HEIGHT; i++) {
            if(buffer[i] != video_memory[i]) {
                buffer[i] = video_memory[i];
            }
        }
    }
    
    void update_cursor() {
        uint16_t pos = cursor_y * VGA_WIDTH + cursor_x;
        outb(0x3D4, 14);
        outb(0x3D5, pos >> 8);
        outb(0x3D4, 15);
        outb(0x3D5, pos & 0xFF);
    }
    
    void check_system_status() {
        check_memory_integrity();
        verify_task_states();
    }
    
    void check_memory_integrity() {
        for(uint32_t i = 0; i < region_count; i++) {
            verify_memory_region(protected_regions[i]);
        }
    }
    
    void verify_memory_region(const MemoryRegion& region) {
        volatile uint8_t* mem = (uint8_t*)region.start;
        for(uint64_t i = 0; i < region.size; i++) {
            mem[i];  // Just access to check for page faults
        }
    }
    
    void verify_task_states() {
        uint32_t active_count = 0;
        for(uint32_t i = 0; i < MAX_TASKS; i++) {
            if(tasks[i].active) {
                active_count++;
            }
        }
        task_count = active_count;
    }
    
    inline void outb(uint16_t port, uint8_t val) {
        asm volatile("outb %0, %1" : : "a"(val), "Nd"(port));
    }
    
    inline uint8_t inb(uint16_t port) {
        uint8_t ret;
        asm volatile("inb %1, %0" : "=a"(ret) : "Nd"(port));
        return ret;
    }
    
    void send_eoi(uint8_t irq) {
        if(irq >= 8) {
            outb(0xA0, 0x20);
        }
        outb(0x20, 0x20);
    }
    
    void handle_keyboard() {
        uint8_t scancode = inb(0x60);
        process_keypress(scancode);
        send_eoi(1);
    }
    
    void handle_timer() {
        update_task_timers();
        send_eoi(8);
    }
    
    void process_keypress(uint8_t scancode) {
        // Handle keyboard input
        if(scancode < 0x80) {
            // Key press
            update_keyboard_buffer(scancode);
        }
    }
    
    void update_keyboard_buffer(uint8_t scancode) {
        static uint8_t buffer[16];
        static uint32_t buffer_pos = 0;
        
        buffer[buffer_pos++] = scancode;
        if(buffer_pos >= 16) buffer_pos = 0;
    }
    
    void update_task_timers() {
        for(uint32_t i = 0; i < MAX_TASKS; i++) {
            if(tasks[i].active && tasks[i].time_slice > 0) {
                tasks[i].time_slice--;
            }
        }
    }
};

extern "C" void kernel_main() {
    PhoneOS os;
    os.init();
    os.run();
}
