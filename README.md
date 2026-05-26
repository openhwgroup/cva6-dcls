# Dual-Core Lock-Step Module for CVA6

`cva6_dcls` wraps two CVA6 RV64 cores in a Dual Modular Redundancy (DMR) configuration for hardware fault detection in safety-critical designs.

# Prerequisites

- [Bender](https://github.com/pulp-platform/bender) — dependency manager (tested with 0.31.0)
- [Verilator](https://www.veripool.org/verilator/) **v5.008** — RTL simulation;
- RISC-V GCC toolchain — cross-compiler targeting `riscv64-unknown-elf` (or `riscv-none-elf`)
- [Spike](https://github.com/riscv-software-src/riscv-isa-sim) built from source — provides both the `spike` binary and `libfesvr`; see [`ci/install-spike.sh`](https://github.com/openhwgroup/cva6/blob/master/ci/install-spike.sh) in the CVA6 repository

Set the following environment variables before running any `make` target:

```sh
export RISCV=/path/to/riscv-toolchain       # directory containing bin/, lib/, include/
export SPIKE_INSTALL_DIR=/path/to/spike      # directory containing bin/spike and lib/libfesvr.so
```

If your toolchain uses a non-default binary prefix (e.g. `riscv-none-elf-gcc` instead of `riscv64-unknown-elf-gcc`), override the compiler variable:

```sh
export RISCV_GCC=/path/to/riscv-none-elf-gcc
```

# Simulating with Verilator

1. Fetch Bender-managed IP dependencies and generate compile scripts:

```sh
make all
```

2. Compile the RTL — generates `sim/verilator/obj_dir/Vcva6_dcls_testharness`:

```sh
make verilate
```

3. Run the `hello_world` smoke test:

```sh
make sim-hello_world
```

Expected output:

```
0: Hello World !
1: Hello World !
2: Hello World !
3: Hello World !
4: Hello World !
.../hello_world.elf *** SUCCESS *** (tohost = 0) after N cycles
```

Logs and trace files are written to `sim/verilator/results/hello_world/`.

## Running custom tests

Place a `.c` file in `sim/verilator/tests/` and run:

```sh
make sim-test TEST=<name>
```

To run a pre-built ELF directly:

```sh
make run ELF=/absolute/path/to/test.elf
```

# Directory Structure

```
rtl/src/          RTL source: cva6_dcls.sv (DCLS top-level wrapper)
tb/               Verilator testbench: cva6_dcls_testharness.sv
sim/verilator/    Simulation driver (sim_main.cpp), BSP, patches, test programs
sim/vsim/         Questa/ModelSim support (planned)
target/sim/       Bender-generated compile scripts (gitignored)
```

# Contributing

Please review [CONTRIBUTING](CONTRIBUTING.md) before opening a pull request.
