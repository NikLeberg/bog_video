# Modify this variable to fit your NEORV32 setup (neorv32 home folder)
NEORV32_HOME = ../lib/neorv32

# Compiler toolchain
RISCV_PREFIX = riscv32-unknown-elf-

# CPU architecture
MARCH = rv32i_zicsr_zifencei

# User flags for additional configuration (will be added to compiler flags)
USER_FLAGS := $(CLI_FLAGS)
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=32K
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=8M
USER_FLAGS += -Og
USER_FLAGS += -DSTDIO_SEMIHOSTING -DUART_SEMIHOSTING

# Add application sources
APP_SRC += $(wildcard ./src/*.c) $(wildcard ./src/*.s) $(wildcard ./src/*.cpp) $(wildcard ./src/*.S)
APP_INC += -I ./include

# Include the common neorv32 buildsystem. Provides targets like exe, bin etc.
include $(NEORV32_HOME)/sw/common/common.mk
