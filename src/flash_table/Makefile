###############################################################################
# Builds the flash_table_gen host tool, which serializes the SPI-NAND flash
# table at build time so BL2 can locate matching flash entries at runtime.
#
# The tool runs on the build host, so it links against host libc and is
# compiled with HOSTCC (gcc by default). CROSS_COMPILE is intentionally not
# used here.
###############################################################################

# Resolve the project root regardless of the working directory.
TOP_DIR ?= $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)

include $(TOP_DIR)/config.mk

INC_DIR := $(TOP_DIR)/src/include

# FLASH_TABLE_OPEN switches the source file to its host-tool entry point
# (main()), which writes the binary table to disk instead of registering it
# at runtime.
CFLAGS  := -fPIC -O2 -Wall
CFLAGS  += -DFLASH_TABLE_OPEN
CFLAGS  += $(TCSUPPORT_DEFS)
CFLAGS  += -I$(INC_DIR)

LDFLAGS := -lm

SRC     := spi_nand_flash_table.c
TARGET  := flash_table_gen

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SRC)
	$(HOSTCC) $(CFLAGS) $(SRC) -o $@ $(LDFLAGS)

clean:
	rm -f $(TARGET) *.o flash_table.bin
