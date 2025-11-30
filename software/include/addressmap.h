#ifndef _ADDRESSMAP_H_
#define _ADDRESSMAP_H_

// External SRAM/main memory:
#define ERAM_BASE           0x00000
#define ERAM_END            0x40000

// Internal SRAM:
#define IRAM_BASE           0x40000
#define IRAM_END            (IRAM_BASE + 0x02000)

// Audio processing unit address space (accessible to both CPU and APU):
#define APU_BASE            0x60000
#define APU_RAM_BASE        APU_BASE
#define APU_RAM_END         (APU_RAM_BASE + 0x800)

#define APU_PERI_BASE       (APU_BASE + 0x8000)
#define APU_IPC_BASE        (APU_PERI_BASE + 0x0000)
#define APU_AOUT_BASE       (APU_PERI_BASE + 0x1000)
#define APU_TIMER_BASE      (APU_PERI_BASE + 0x2000)
#define APU_SPI_STREAM_BASE (APU_PERI_BASE + 0x3000)

// CPU peripherals:
#define PERI_BASE           0x70000
#define TIMER_BASE          (PERI_BASE + 0x0000)
#define PADCTRL_BASE        (PERI_BASE + 0x1000)
#define PPU_BASE            (PERI_BASE + 0x2000)
#define DISP_BASE           (PERI_BASE + 0x3000)
#define VUART_DEV_BASE      (PERI_BASE + 0x4000)
#define GPIO_BASE           (PERI_BASE + 0x5000)
#define UART_BASE           (PERI_BASE + 0x6000)

#ifndef __ASSEMBLER__

#include <stdint.h>

#define DECL_REG(addr, name) volatile uint32_t * const (name) = (volatile uint32_t*)(addr)

#define __time_critical __attribute__((section(".time_critical")))

typedef volatile uint32_t io_rw_32;

#endif

#endif // _ADDRESSMAP_H_
