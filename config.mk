###############################################################################
# Build configuration for make_airoha_atf.
#
# Resolution order for every TCSUPPORT_* / toolchain variable:
#   1. command-line override (e.g. `make TCSUPPORT_BL2_OPTIMIZATION=1`)
#   2. value set in configs/<PLATFORM>.mk (uses ":=" to win over defaults)
#   3. fallback default in this file (uses "?=" so it only fills gaps)
#
# TCSUPPORT_DEFS expands every flag whose value is "1" into a -D<name>=1
# argument, so sub-Makefiles can simply append $(TCSUPPORT_DEFS) to CFLAGS.
###############################################################################

# Absolute path to the directory holding this fragment, used to locate the
# per-platform override files regardless of the working directory.
CONFIG_MK_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

# Selected target SoC. Each platform must have a matching configs/<name>.mk
# and a populated unopen_img/<name>/ input directory.
PLATFORM ?= an7563

# Apply IC-specific overrides before any default, so values defined there
# shadow the "?=" defaults further down.
-include $(CONFIG_MK_DIR)/configs/$(PLATFORM).mk

# Cross-compile toolchain settings reserved for future ARM 32-bit targets.
# The flash_table generator runs on the build host, so it always uses HOSTCC
# instead of CROSS_COMPILE.
CROSS_COMPILE       ?= arm-linux-gnueabihf-
ARM_ARCH            ?= aarch32
ARM_INSTRUCTION_SET ?= A32
HOSTCC              ?= gcc

# flash_table host tool feature toggles.
TCSUPPORT_BL2_OPTIMIZATION       ?= 1
TCSUPPORT_NAND_FLASH_OTP         ?=
TCSUPPORT_AUTOBENCH              ?=
TCSUPPORT_PARALLEL_NAND          ?=
TCSUPPORT_SECURE_BOOT_FLASH_OTP  ?=
TCSUPPORT_CPU_ARMV8              ?=
CONFIG_ECNT_UBOOT                ?=

# trx host tool feature toggles.
TCSUPPORT_OPENWRT                ?= 1
TCSUPPORT_LITTLE_ENDIAN          ?= 1
TCSUPPORT_BB_256KB               ?=
BOOTROM_LARGE_SIZE               ?=
TCSUPPORT_CMCCV2                 ?=
TCSUPPORT_SECURE_BOOT            ?=
TCSUPPORT_SECURE_BOOT_V1         ?=
TCSUPPORT_SECURE_BOOT_V2         ?=
TCSUPPORT_BOOTROM_LARGE_SIZE     ?=

# Master list of every flag that participates in TCSUPPORT_DEFS expansion.
# Keep this list in sync with the toggles above and with configs/*.mk.
TCSUPPORT_FLAGS := \
	TCSUPPORT_BL2_OPTIMIZATION \
	TCSUPPORT_NAND_FLASH_OTP \
	TCSUPPORT_AUTOBENCH \
	TCSUPPORT_PARALLEL_NAND \
	TCSUPPORT_SECURE_BOOT_FLASH_OTP \
	TCSUPPORT_CPU_ARMV8 \
	CONFIG_ECNT_UBOOT \
	TCSUPPORT_OPENWRT \
	TCSUPPORT_LITTLE_ENDIAN \
	TCSUPPORT_BB_256KB \
	BOOTROM_LARGE_SIZE \
	TCSUPPORT_CMCCV2 \
	TCSUPPORT_SECURE_BOOT \
	TCSUPPORT_SECURE_BOOT_V1 \
	TCSUPPORT_SECURE_BOOT_V2 \
	TCSUPPORT_BOOTROM_LARGE_SIZE

# For every flag whose value is exactly "1", emit "-D<flag>=1".
TCSUPPORT_DEFS := $(foreach f,$(TCSUPPORT_FLAGS),$(if $(filter 1,$($(f))),-D$(f)=1))

# Propagate the configuration to recursive $(MAKE) invocations.
export $(TCSUPPORT_FLAGS)
export PLATFORM CROSS_COMPILE ARM_ARCH ARM_INSTRUCTION_SET HOSTCC
