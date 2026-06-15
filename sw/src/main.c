/**
 * @file main.c
 * @author Niklaus Leuenberger <@NikLeberg>
 * @brief Main application for NEORV32 processor.
 *
 * SPDX-License-Identifier: MIT
 */

#include <neorv32.h>

int main(void) {
    uint32_t cnt = 0;
    for (;;) {
        neorv32_gpio_port_set(cnt);
        cnt++;
    }
}
