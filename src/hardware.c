#include "hardware.h"

void init_hardware() {
    setup_cpu();
    init_memory();
    configure_display();
}

void setup_interrupts() {
    register_handlers();
    enable_irq();
}
