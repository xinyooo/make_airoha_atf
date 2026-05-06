###############################################################################
# Per-IC overrides for the AN7563 SoC.
#
# Only flags that exist in BOTH the IC profile and config.mk's TCSUPPORT_FLAGS
# list are listed here. Values use ":=" so the "?=" defaults in config.mk do
# not overwrite them.
###############################################################################

# Selects the size-optimised BL2 flash table layout.
TCSUPPORT_BL2_OPTIMIZATION   := 1

# Targets the ARMv8 SRAM address map used by the flash table consumer at boot.
TCSUPPORT_CPU_ARMV8          := 1

# Picks the OpenWrt build flow inside the trx host tool.
TCSUPPORT_OPENWRT            := 1

# Configures the trx tool for the larger bootrom image layout.
TCSUPPORT_BOOTROM_LARGE_SIZE := 1
