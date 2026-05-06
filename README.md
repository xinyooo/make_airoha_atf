# make_airoha_atf

A standalone project that re-packages BL2 (and compresses BL31) for Airoha
SoCs whose vendor BL2 is delivered as separate `bl21` / `bl22` / `bl23`
fragments. The project bundles the SPI-NAND flash table generator, the
required host tools (`lzma`, `trx`), and a thin Makefile pipeline.

## When to use this project

Only SoCs whose `unopen_img/<ic>/` directory ships the split layout

```
bl21.bin
bl22.lzma
bl23.lzma
bl31.bin
```

need this project. Platforms that already provide a finished `bl2.bin`
(such as AN7581, AN7583, EN7523 in the upstream tree) are pre-assembled and
can be flashed as-is — running this project on them would be redundant.

The current reference platform that *does* require packaging is `an7563`.

## Repository layout

```
make_airoha_atf/
├── Makefile               # Top-level pipeline (bl2 + bl31).
├── config.mk              # Cross-platform defaults and TCSUPPORT_DEFS expansion.
├── configs/               # One file per SoC, holding only its IC overrides.
│   └── an7563.mk
├── .gitignore
├── README.md
├── src/
│   ├── flash_table/
│   │   ├── Makefile                  # Builds the flash_table_gen host tool.
│   │   └── spi_nand_flash_table.c    # SPI-NAND table source.
│   └── include/
│       └── spi/
│           ├── spi_nand_flash.h
│           └── nand_flash_otp.h
├── tools/
│   ├── lzma                          # Prebuilt host binary.
│   └── trx/
│       ├── Makefile                  # Optional rebuild via `make trx_build`.
│       ├── trx                       # Prebuilt host binary.
│       ├── trx.c
│       ├── trx.h
│       └── trx_config
├── unopen_img/
│   └── an7563/                       # Inputs: bl1.bin, bl21.bin, bl22.lzma,
│                                     #         bl23.lzma, bl31.bin
└── build/                            # Generated outputs (git-ignored).
    └── <PLATFORM>/
        ├── bl2.bin
        └── bl31.lzma
```

## Toolchain

- `flash_table_gen` is a **host tool**: it runs on the build machine to emit
  `flash_table.bin`, so it always uses `HOSTCC` (defaults to `gcc`).
- ARM 32-bit cross-compile variables are exposed for any future ARM target
  that may be added later:

  ```make
  CROSS_COMPILE       ?= arm-linux-gnueabihf-
  ARM_ARCH            ?= aarch32
  ARM_INSTRUCTION_SET ?= A32
  ```

## Quick start

```bash
# Default: build bl2.bin and bl31.lzma for PLATFORM=an7563.
make

# Choose a platform explicitly.
make PLATFORM=an7563

# Build a single artifact.
make bl2
make bl31

# Verbose mode prints every command.
make V=1

# Inspect the resolved configuration.
make help

# Cleanup.
make clean         # removes build/ and host tool object files.
make distclean     # also cleans rebuilt trx intermediates.
```

Outputs land in:

```
build/<PLATFORM>/bl2.bin
build/<PLATFORM>/bl31.lzma
```

## Pipeline overview

| Stage | Command equivalent                                                                  | Output                              |
| ----- | ----------------------------------------------------------------------------------- | ----------------------------------- |
| 1     | Build `flash_table_gen` (host tool)                                                 | `src/flash_table/flash_table_gen`   |
| 2     | Run `flash_table_gen` inside `build/<PLATFORM>/`                                    | `flash_table.bin` (intermediate)    |
| 3     | `lzma e flash_table.bin flash_table.lzma`                                           | `flash_table.lzma` (intermediate)   |
| 4     | `trx -z bl21.bin bl22.lzma bl23.lzma flash_table.lzma bl2.bin`                      | `build/<PLATFORM>/bl2.bin`          |
| 5     | `cp bl2.bin bl2.tmp` + `trx -x bl2.tmp bl2_crc.bin` + `mv bl2_crc.bin bl2.bin`      | `build/<PLATFORM>/bl2.bin` (CRC)    |
| 6     | `lzma e bl31.bin bl31.lzma`                                                         | `build/<PLATFORM>/bl31.lzma`        |

## Configuration model

### Layered resolution

```
top Makefile
└── include config.mk
    ├── PLATFORM defaults to an7563 (override on command line if needed)
    ├── -include configs/$(PLATFORM).mk    # IC-specific overrides (":=")
    └── default values for every TCSUPPORT_* / toolchain variable ("?=")
```

`configs/<PLATFORM>.mk` uses **immediate** assignments (`:=`), so the `?=`
defaults that follow in `config.mk` cannot overwrite them. Anything not set
by the IC config simply inherits the default.

### IC config = intersection of profile and config.mk

A `configs/<ic>.mk` file lists **only the flags that are present in both**:

1. The IC's vendor profile (e.g. `UNION_<...>.mak`).
2. `config.mk`'s `TCSUPPORT_FLAGS` master list.

Any flag missing from either side stays out of the IC config. As a worked
example, `configs/an7563.mk` contains four entries because those are the
only flags that the AN7563 profile and `config.mk` agree on:

| `config.mk` flag                | In AN7563 profile? | `configs/an7563.mk` |
| ------------------------------- | ------------------ | ------------------- |
| `TCSUPPORT_BL2_OPTIMIZATION`    | yes                | `:= 1`              |
| `TCSUPPORT_CPU_ARMV8`           | yes                | `:= 1`              |
| `TCSUPPORT_OPENWRT`             | yes                | `:= 1`              |
| `TCSUPPORT_BOOTROM_LARGE_SIZE`  | yes                | `:= 1`              |
| `TCSUPPORT_NAND_FLASH_OTP`      | no                 | (omitted)           |
| `TCSUPPORT_AUTOBENCH`           | no                 | (omitted)           |
| `TCSUPPORT_PARALLEL_NAND`       | no                 | (omitted)           |
| `TCSUPPORT_SECURE_BOOT_FLASH_OTP` | no               | (omitted)           |
| `CONFIG_ECNT_UBOOT`             | no                 | (omitted)           |
| `TCSUPPORT_LITTLE_ENDIAN`       | no                 | (omitted, default 1)|
| `TCSUPPORT_BB_256KB`            | no                 | (omitted)           |
| `BOOTROM_LARGE_SIZE`            | no                 | (omitted)           |
| `TCSUPPORT_CMCCV2`              | no                 | (omitted)           |
| `TCSUPPORT_SECURE_BOOT`         | no                 | (omitted)           |
| `TCSUPPORT_SECURE_BOOT_V1`      | no                 | (omitted)           |
| `TCSUPPORT_SECURE_BOOT_V2`      | no                 | (omitted)           |

### Adding a new IC

1. Stage the inputs under `unopen_img/<ic>/` (must contain at least
   `bl21.bin`, `bl22.lzma`, `bl23.lzma`, `bl31.bin`).
2. Locate the IC's vendor profile.
3. Create `configs/<ic>.mk` containing only the intersection described
   above; remember to use `:=`.
4. Run `make PLATFORM=<ic>`.

## TCSUPPORT_* reference

### flash_table host tool

| Flag                              | Default | Effect                                                            |
| --------------------------------- | ------- | ----------------------------------------------------------------- |
| `TCSUPPORT_BL2_OPTIMIZATION`      | `1`     | Selects the size-optimised BL2 flash table layout.                |
| `TCSUPPORT_NAND_FLASH_OTP`        |         | Includes OTP page metadata in each table entry.                   |
| `TCSUPPORT_AUTOBENCH`             |         | Excludes NAND entries that are not relevant for autobench builds. |
| `TCSUPPORT_PARALLEL_NAND`         |         | Enables parallel NAND support.                                    |
| `TCSUPPORT_SECURE_BOOT_FLASH_OTP` |         | Enables the NAND OTP RSA public-key interface.                    |
| `TCSUPPORT_CPU_ARMV8`             |         | Targets the ARMv8 SRAM address map.                               |
| `CONFIG_ECNT_UBOOT`               |         | U-Boot build context.                                             |

`FLASH_TABLE_OPEN` is always injected by the sub-Makefile and is required
for the host build.

### trx host tool

| Flag                            | Default | Effect                                              |
| ------------------------------- | ------- | --------------------------------------------------- |
| `TCSUPPORT_OPENWRT`             | `1`     | Uses the OpenWrt build flow.                        |
| `TCSUPPORT_LITTLE_ENDIAN`       | `1`     | Generates little-endian output for ARM 32-bit.      |
| `TCSUPPORT_BB_256KB`            |         | Uses a 256 KB bootbase layout.                      |
| `BOOTROM_LARGE_SIZE`            |         | Uses the 128 KB bootbase layout.                    |
| `TCSUPPORT_CMCCV2`              |         | CMCC v2 customisation.                              |
| `TCSUPPORT_SECURE_BOOT`         |         | Enables secure boot.                                |
| `TCSUPPORT_SECURE_BOOT_V1` / `V2` |       | Selects the secure boot sub-version.                |
| `TCSUPPORT_BOOTROM_LARGE_SIZE`  |         | Enables the larger bootrom configuration.           |

`TCSUPPORT_DEFS` automatically expands every flag set to `1` into
`-D<flag>=1`; sub-Makefiles can drop `$(TCSUPPORT_DEFS)` straight into their
CFLAGS.

## .gitignore

Ignored:

- `build/`, `out/` — every generated artifact (bl2.bin, bl31.lzma, intermediates).
- `src/flash_table/flash_table_gen` and its `*.o` objects.
- `tools/trx/*.o`, `*.a` from optional rebuilds.
- Editor / IDE noise (`.vscode/`, `.idea/`, `*.swp`, `*~`, `.DS_Store`, `__pycache__/`).

Tracked:

- All sources (`src/`).
- All configuration (`config.mk`, `configs/`).
- Prebuilt host tools (`tools/lzma`, `tools/trx/trx`).
- Per-platform inputs (`unopen_img/<ic>/`).

## Notes and limitations

- The BL2 packaging path is only meaningful for SoCs that ship the split
  bl21 / bl22 / bl23 layout. The `check-bl2-inputs` target stops the build
  early if any required input is missing.
- The BL31 path simply lzma-compresses `unopen_img/<ic>/bl31.bin`; nothing
  else is required.
- `flash_table_gen` writes its output in the current working directory, so
  the Makefile cd's into `build/<PLATFORM>/` before invoking it to keep the
  output co-located with the rest of the build artifacts.
- The shipped `lzma` and `trx` binaries are 64-bit Linux ELF executables. If
  they are not compatible with the build host, rebuild `trx` via
  `make trx_build` (a separate `lzma` source must be obtained for `lzma`).
