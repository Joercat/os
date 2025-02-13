#include <stdint.h>

class PhoneOS {
private:
    static constexpr uint16_t VGA_WIDTH = 80;
    static constexpr uint16_t VGA_HEIGHT = 25;
    uint16_t* video_memory = (uint16_t*)0xB8000;
    
    struct IDTEntry {
        uint16_t offset_low;
        uint16_t selector;
        uint8_t ist;
        uint8_t type_attr;
        uint16_t offset_mid;
        uint32_t offset_high;
        uint32_t zero;
    } __attribute__((packed));

    IDTEntry idt[256];
    
public:
    void init() {
        setup_interrupts();
        init_video();
        setup_paging();
    }
    
    void setup_interrupts() {
        for (int i = 0; i < 256; i++) {
            idt[i].selector = 0x08;
            idt[i].type_attr = 0x8E;
        }
        load_idt();
        enable_pic();
    }
    
    void init_video() {
        for (int i = 0; i < VGA_WIDTH * VGA_HEIGHT; i++) {
            video_memory[i] = 0x0F20;
        }
    }
    
    void setup_paging() {
        uint64_t* pml4 = (uint64_t*)0x1000;
        for (int i = 0; i < 512; i++) {
            pml4[i] = 0x2000 | 0x3;
        }
        asm volatile("mov %0, %%cr3" : : "r"(pml4));
    }
    
    void run() {
        while(true) {
            process_interrupts();
            schedule_tasks();
            update_display();
        }
    }

private:
    inline void outb(uint16_t port, uint8_t val) {
        asm volatile("outb %0, %1" : : "a"(val), "Nd"(port));
    }
    
    void enable_pic() {
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
    }
    
    void load_idt() {
        struct {
            uint16_t limit;
            uint64_t base;
        } __attribute__((packed)) IDTR = {
            sizeof(idt) - 1,
            (uint64_t)idt,
        };
        asm volatile("lidt %0" : : "m"(IDTR));
    }
    
    void process_interrupts() {
        handle_hardware_events();
        handle_system_calls();
    }
    
    void schedule_tasks() {
        update_task_queue();
        switch_context();
    }
    
    void update_display() {
        refresh_screen_buffer();
        update_cursor();
    }
};

extern "C" void kernel_main() {
    PhoneOS os;
    os.init();
    os.run();
}
