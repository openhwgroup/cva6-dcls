# Copyright 2026 ETH Zurich, University of Bologna, Fondazione Chips-IT, Eclipse Foundation
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

BENDER ?= bender
verilator ?= verilator
CXX ?= g++

VLOG_ARGS  ?= -timescale 1ns/1ps
VLT_ARGS   ?=

NUM_JOBS ?= $(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)

# Tool paths used by the CVA6 C++ DPI simulation code.
# Pass these on the make command line if they are not exported in the shell.
RISCV ?=
SPIKE_INSTALL_DIR ?=

# Target configuration for CVA6
BENDER_CVA6_TARGET ?= -t cv64a6_imafdc_sv39_hpdcache_wb
# Common targets for RTL simulation
BENDER_CVA6_DCLS_RTL_TARGETS ?= -t rtl $(BENDER_CVA6_TARGET)

# Define useful paths
CVA6_DCLS_ROOT	?= $(shell realpath -eP .)
CVA6_ROOT	?= $(shell $(BENDER) path cva6)
APB_ROOT	?= $(shell $(BENDER) path apb)
REDUNDANCY_CELLS_ROOT	?= $(shell $(BENDER) path redundancy_cells)
REGISTER_INTERFACE_ROOT	?= $(shell $(BENDER) path register_interface)

VERILATOR_BUILD_DIR	?= $(CVA6_DCLS_ROOT)/sim/verilator/obj_dir

CVA6_DCLS_GENERATED_SIM_FILES ?= \
	$(CVA6_DCLS_ROOT)/target/sim/vsim/compile.dcls.tcl \
	$(CVA6_DCLS_ROOT)/target/sim/vlt/compile.dcls.vlt

CVA6_DCLS_VLT_INCDIRS	?= \
	$(CVA6_ROOT)/vendor/pulp-platform/common_cells/include \
	$(CVA6_ROOT)/vendor/pulp-platform/axi/include \
	$(CVA6_ROOT)/core/include \
	$(CVA6_ROOT)/core/cache_subsystem/hpdcache/rtl/include \
	$(CVA6_ROOT)/core/cache_subsystem/hpdcache/rtl/src/utils/ecc \
	$(CVA6_ROOT)/corev_apu/tb/common \
	$(CVA6_ROOT)/corev_apu/instr_tracing/ITI/include \
	$(CVA6_ROOT)/verif/tb/core \
	$(REDUNDANCY_CELLS_ROOT)/include \
	$(REGISTER_INTERFACE_ROOT)/include
	
CVA6_DCLS_VLT_INCDIR_ARGS = $(addprefix +incdir+,$(CVA6_DCLS_VLT_INCDIRS))

CVA6_DCLS_VLT_SOC_FILES ?= \
	$(CVA6_ROOT)/corev_apu/tb/ariane_axi_pkg.sv \
	$(CVA6_ROOT)/corev_apu/tb/ariane_soc_pkg.sv \
	$(CVA6_ROOT)/corev_apu/riscv-dbg/src/dm_pkg.sv \
	$(CVA6_ROOT)/corev_apu/tb/ariane_axi_soc_pkg.sv \
	$(CVA6_ROOT)/corev_apu/instr_tracing/ITI/include/iti_pkg.sv \
	$(CVA6_ROOT)/corev_apu/instr_tracing/rv_tracer-main/include/te_pkg.sv \
	$(CVA6_ROOT)/corev_apu/instr_tracing/rv_encapsulator-main/src/include/encap_pkg.sv \
	$(CVA6_ROOT)/core/cva6_rvfi.sv \
	$(CVA6_ROOT)/corev_apu/bootrom/bootrom.sv \
	$(CVA6_ROOT)/corev_apu/clint/axi_lite_interface.sv \
	$(CVA6_ROOT)/corev_apu/clint/clint.sv \
	$(CVA6_ROOT)/corev_apu/fpga/src/axi2apb/src/axi2apb_64_32.sv \
	$(CVA6_ROOT)/corev_apu/fpga/src/axi2apb/src/axi2apb.sv \
	$(CVA6_ROOT)/corev_apu/fpga/src/axi2apb/src/axi2apb_wrap.sv \
	$(CVA6_ROOT)/corev_apu/fpga/src/apb_timer/apb_timer.sv \
	$(CVA6_ROOT)/corev_apu/fpga/src/apb_timer/timer.sv \
	$(CVA6_ROOT)/corev_apu/fpga/src/axi_slice/src/axi_ar_buffer.sv \
	$(CVA6_ROOT)/corev_apu/fpga/src/axi_slice/src/axi_aw_buffer.sv \
	$(CVA6_ROOT)/corev_apu/fpga/src/axi_slice/src/axi_b_buffer.sv \
	$(CVA6_ROOT)/corev_apu/fpga/src/axi_slice/src/axi_r_buffer.sv \
	$(CVA6_ROOT)/corev_apu/fpga/src/axi_slice/src/axi_single_slice.sv \
	$(CVA6_ROOT)/corev_apu/fpga/src/axi_slice/src/axi_slice.sv \
	$(CVA6_ROOT)/corev_apu/fpga/src/axi_slice/src/axi_slice_wrap.sv \
	$(CVA6_ROOT)/corev_apu/fpga/src/axi_slice/src/axi_w_buffer.sv \
	$(CVA6_ROOT)/vendor/pulp-platform/axi_riscv_atomics/src/axi_res_tbl.sv \
	$(CVA6_ROOT)/vendor/pulp-platform/axi_riscv_atomics/src/axi_riscv_amos_alu.sv \
	$(CVA6_ROOT)/vendor/pulp-platform/axi_riscv_atomics/src/axi_riscv_amos.sv \
	$(CVA6_ROOT)/vendor/pulp-platform/axi_riscv_atomics/src/axi_riscv_atomics.sv \
	$(CVA6_ROOT)/vendor/pulp-platform/axi_riscv_atomics/src/axi_riscv_atomics_wrap.sv \
	$(CVA6_ROOT)/vendor/pulp-platform/axi_riscv_atomics/src/axi_riscv_lrsc.sv \
	$(CVA6_ROOT)/vendor/pulp-platform/axi_riscv_atomics/src/axi_riscv_lrsc_wrap.sv \
	$(CVA6_ROOT)/corev_apu/axi_mem_if/src/axi2mem.sv \
	$(CVA6_ROOT)/corev_apu/riscv-dbg/src/dm_csrs.sv \
	$(CVA6_ROOT)/corev_apu/riscv-dbg/src/dmi_cdc.sv \
	$(CVA6_ROOT)/corev_apu/riscv-dbg/src/dmi_jtag.sv \
	$(CVA6_ROOT)/corev_apu/riscv-dbg/src/dmi_jtag_tap.sv \
	$(CVA6_ROOT)/corev_apu/riscv-dbg/src/dm_mem.sv \
	$(CVA6_ROOT)/corev_apu/riscv-dbg/src/dm_sba.sv \
	$(CVA6_ROOT)/corev_apu/riscv-dbg/src/dm_top.sv \
	$(CVA6_ROOT)/corev_apu/rv_plic/rtl/rv_plic_target.sv \
	$(CVA6_ROOT)/corev_apu/rv_plic/rtl/rv_plic_gateway.sv \
	$(CVA6_ROOT)/corev_apu/rv_plic/rtl/plic_regmap.sv \
	$(CVA6_ROOT)/corev_apu/rv_plic/rtl/plic_top.sv \
	$(CVA6_ROOT)/corev_apu/riscv-dbg/debug_rom/debug_rom.sv \
	$(CVA6_ROOT)/corev_apu/tb/ariane_peripherals.sv \
	$(CVA6_ROOT)/corev_apu/tb/common/uart.sv \
	$(CVA6_ROOT)/corev_apu/tb/rvfi_tracer.sv \
	$(CVA6_ROOT)/corev_apu/tb/common/SimDTM.sv \
	$(CVA6_ROOT)/corev_apu/tb/common/SimJTAG.sv \
	$(CVA6_ROOT)/corev_apu/instr_tracing/ITI/cva6_iti/iti.sv \
	$(CVA6_ROOT)/corev_apu/instr_tracing/ITI/cva6_iti/block_retirement.sv \
	$(CVA6_ROOT)/corev_apu/instr_tracing/ITI/cva6_iti/single_retirement.sv \
	$(CVA6_ROOT)/corev_apu/instr_tracing/ITI/cva6_iti/itype_detector.sv \
	$(CVA6_ROOT)/corev_apu/instr_tracing/rv_tracer-main/rtl/te_branch_map.sv \
	$(CVA6_ROOT)/corev_apu/instr_tracing/rv_tracer-main/rtl/te_filter.sv \
	$(CVA6_ROOT)/corev_apu/instr_tracing/rv_tracer-main/rtl/te_packet_emitter.sv \
	$(CVA6_ROOT)/corev_apu/instr_tracing/rv_tracer-main/rtl/te_priority.sv \
	$(CVA6_ROOT)/corev_apu/instr_tracing/rv_tracer-main/rtl/te_reg.sv \
	$(CVA6_ROOT)/corev_apu/instr_tracing/rv_tracer-main/rtl/te_resync_counter.sv \
	$(CVA6_ROOT)/corev_apu/instr_tracing/rv_tracer-main/rtl/rv_tracer.sv \
	$(CVA6_ROOT)/corev_apu/instr_tracing/DPTI/slicer_DPTI.sv \
	$(CVA6_ROOT)/corev_apu/instr_tracing/rv_encapsulator-main/src/rtl/encapsulator.sv

CVA6_DCLS_VLT_CFLAGS = -std=c++17 -O3 -DVL_DEBUG \
	-I$(SPIKE_INSTALL_DIR)/include \
	-I$(CVA6_ROOT)/corev_apu/tb/dpi \
	-I$(RISCV)/include
	
CVA6_DCLS_VLT_LDFLAGS = -L$(RISCV)/lib -L$(SPIKE_INSTALL_DIR)/lib \
	-Wl,-rpath,$(RISCV)/lib \
	-Wl,-rpath,$(SPIKE_INSTALL_DIR)/lib \
	-lfesvr -lriscv -ldisasm -lyaml-cpp -lpthread
	
CVA6_DCLS_VERILATOR_FLAGS ?= -Wall -Wno-PINMISSING -Wno-IMPLICIT -Wno-MODDUP\
	-Wno-fatal -Wno-PINCONNECTEMPTY -Wno-ASSIGNDLY -Wno-DECLFILENAME \
	-Wno-UNUSED -Wno-UNOPTFLAT -Wno-BLKANDNBLK -Wno-style \
	--unroll-count 256
	
################
# Dependencies #
################

BENDER_ROOT ?= $(CVA6_DCLS_ROOT)/.bender

$(BENDER_ROOT)/.cva6_dcls_deps: $(CVA6_DCLS_ROOT)/Bender.yml $(CVA6_DCLS_ROOT)/Bender.lock
	$(BENDER) checkout
	cd $(CVA6_DCLS_ROOT) && git submodule update --init --recursive
	@touch $@

ifeq ($(shell test -f $(BENDER_ROOT)/.cva6_dcls_deps && echo 1),)
-include $(BENDER_ROOT)/.cva6_dcls_deps
endif

.PHONY: clean-deps
clean-deps:
	rm -rf .bender
	cd $(CVA6_DCLS_ROOT) && git submodule deinit --all

CVA6_DCLS_HW_ALL += $(BENDER_ROOT)/.cva6_dcls_deps

##############
# Simulation #
##############

$(CVA6_DCLS_ROOT)/target/sim/vsim/compile.dcls.tcl: $(CVA6_DCLS_ROOT)/Bender.yml $(CVA6_DCLS_ROOT)/Bender.lock
	$(BENDER) script vsim -t sim -t test $(BENDER_CVA6_DCLS_RTL_TARGETS) --vlog-args="$(VLOG_ARGS)" > $@

$(CVA6_DCLS_ROOT)/target/sim/vlt/compile.dcls.vlt: $(CVA6_DCLS_ROOT)/Bender.yml $(CVA6_DCLS_ROOT)/Bender.lock
	$(BENDER) script verilator -t sim $(BENDER_CVA6_DCLS_RTL_TARGETS) --vlt-args="$(VLT_ARGS)" > $@

CVA6_DCLS_SIM_ALL += $(CVA6_DCLS_ROOT)/target/sim/vsim/compile.dcls.tcl
CVA6_DCLS_SIM_ALL += $(CVA6_DCLS_ROOT)/target/sim/vlt/compile.dcls.vlt

.PHONY: check-verilator-env verilate verilator clean-verilator

check-verilator-env:
	@command -v $(verilator) >/dev/null || \
		(echo "ERROR: verilator not found. Add it to PATH or run make verilator verilator=/path/to/verilator"; exit 1)
	@test -n "$(RISCV)" || \
		(echo "ERROR: RISCV is not set."; exit 1)
	@test -n "$(SPIKE_INSTALL_DIR)" || \
		(echo "ERROR: SPIKE_INSTALL_DIR is not set"; exit 1)
		
verilate: $(CVA6_DCLS_ROOT)/target/sim/vlt/compile.dcls.vlt $(BENDER_ROOT)/.cva6_dcls_deps check-verilator-env
	@mkdir -p $(VERILATOR_BUILD_DIR)
	cd $(REDUNDANCY_CELLS_ROOT) && git apply $(CVA6_DCLS_ROOT)/sim/verilator/patches/prim_secded_api_compat.patch 2>/dev/null || true
	cd $(CVA6_ROOT) && git apply $(CVA6_DCLS_ROOT)/sim/verilator/patches/cva6_localparam_type.patch 2>/dev/null || true
	$(verilator) --no-timing $(CVA6_ROOT)/verilator_config.vlt \
		-f $(CVA6_DCLS_ROOT)/target/sim/vlt/compile.dcls.vlt \
		$(CVA6_DCLS_VLT_SOC_FILES) \
		$(CVA6_ROOT)/corev_apu/tb/common/mock_uart.sv \
		$(CVA6_DCLS_ROOT)/tb/cva6_dcls_testharness.sv \
		$(CVA6_DCLS_VLT_INCDIR_ARGS) \
		$(CVA6_DCLS_VERILATOR_FLAGS) \
		-CFLAGS "$(CVA6_DCLS_VLT_CFLAGS)" \
		-LDFLAGS "$(CVA6_DCLS_VLT_LDFLAGS)" \
		--cc --vpi --threads-dpi none \
		--top-module cva6_dcls_testharness \
		--Mdir $(VERILATOR_BUILD_DIR) -O3 \
		--exe $(CVA6_DCLS_ROOT)/sim/verilator/sim_main.cpp \
			$(CVA6_ROOT)/corev_apu/tb/dpi/SimDTM.cc \
			$(CVA6_ROOT)/corev_apu/tb/dpi/SimJTAG.cc \
			$(CVA6_ROOT)/corev_apu/tb/dpi/remote_bitbang.cc \
			$(CVA6_ROOT)/corev_apu/tb/dpi/msim_helper.cc \
	|| { \
		cd $(REDUNDANCY_CELLS_ROOT) && git checkout -- rtl/HMR/recovery_rf.sv rtl/HMR/recovery_pc.sv rtl/HMR/recovery_csr.sv 2>/dev/null; \
		cd $(CVA6_ROOT) && git checkout -- core/cva6.sv 2>/dev/null; \
		exit 1; }
	$(MAKE) -C $(VERILATOR_BUILD_DIR) -j$(NUM_JOBS) -f Vcva6_dcls_testharness.mk \
	|| { \
		cd $(REDUNDANCY_CELLS_ROOT) && git checkout -- rtl/HMR/recovery_rf.sv rtl/HMR/recovery_pc.sv rtl/HMR/recovery_csr.sv 2>/dev/null; \
		cd $(CVA6_ROOT) && git checkout -- core/cva6.sv 2>/dev/null; \
		exit 1; }
	cd $(REDUNDANCY_CELLS_ROOT) && git checkout -- rtl/HMR/recovery_rf.sv rtl/HMR/recovery_pc.sv rtl/HMR/recovery_csr.sv 2>/dev/null || true
	cd $(CVA6_ROOT) && git checkout -- core/cva6.sv 2>/dev/null || true

############
# Software #
############

CVA6_CUSTOM_TESTS  ?= $(CVA6_ROOT)/verif/tests/custom
VLT_TESTS_BUILD    ?= $(CVA6_DCLS_ROOT)/sim/verilator/tests/build
VLT_BSP_DIR        ?= $(CVA6_DCLS_ROOT)/sim/verilator/tests/bsp
VLT_TESTS_SRC_DIR  ?= $(CVA6_DCLS_ROOT)/sim/verilator/tests

RISCV_GCC   ?= $(RISCV)/bin/riscv64-unknown-elf-gcc
RISCV_ARCH  ?= rv64gc
RISCV_ABI   ?= lp64d

RISCV_GCC_FLAGS ?= \
	-march=$(RISCV_ARCH) \
	-mabi=$(RISCV_ABI) \
	-mcmodel=medany \
	-static \
	-std=gnu99 \
	-fvisibility=hidden \
	-nostdlib \
	-nostartfiles \
	-I$(CVA6_CUSTOM_TESTS)/env \
	-I$(CVA6_CUSTOM_TESTS)/common

$(VLT_TESTS_BUILD):
	@mkdir -p $@

# Pattern rule: compile any .c placed in $(VLT_TESTS_SRC_DIR) using the CVA6 BSP.
# To add a new test: put <name>.c in sim/verilator/tests/ and run:
#   make build-test TEST=<name>   or   make sim-test TEST=<name>
$(VLT_TESTS_BUILD)/%.elf: $(VLT_TESTS_SRC_DIR)/%.c \
		$(CVA6_CUSTOM_TESTS)/common/syscalls.c \
		$(CVA6_CUSTOM_TESTS)/common/crt.S | $(VLT_TESTS_BUILD)
	$(RISCV_GCC) $(RISCV_GCC_FLAGS) -T$(VLT_BSP_DIR)/link.ld $^ -o $@

# return0 comes from the CVA6 upstream tree (no local copy needed)
$(VLT_TESTS_BUILD)/return0.elf: \
		$(CVA6_CUSTOM_TESTS)/return0/return0.c \
		$(CVA6_CUSTOM_TESTS)/common/syscalls.c \
		$(CVA6_CUSTOM_TESTS)/common/crt.S | $(VLT_TESTS_BUILD)
	$(RISCV_GCC) $(RISCV_GCC_FLAGS) -T$(VLT_BSP_DIR)/link.ld $^ -o $@

.PHONY: build-hello_world build-return0 build-test
build-hello_world: $(VLT_TESTS_BUILD)/hello_world.elf
build-return0:     $(VLT_TESTS_BUILD)/return0.elf
build-test:
	@test -n "$(TEST)" || (echo "ERROR: TEST not specified. Usage: make build-test TEST=<name>"; exit 1)
	$(MAKE) $(VLT_TESTS_BUILD)/$(TEST).elf

#######
# Run #
#######

VLT_SIM         ?= $(VERILATOR_BUILD_DIR)/Vcva6_dcls_testharness
VLT_RESULTS_DIR ?= $(CVA6_DCLS_ROOT)/sim/verilator/results
MAX_CYCLES      ?= 10000000
ELF             ?=
TEST            ?=
SPIKE           ?= $(SPIKE_INSTALL_DIR)/bin/spike

.PHONY: run run-hello_world run-return0 run-spike-hello_world run-spike-return0
.PHONY: sim-hello_world sim-return0 sim-test

# ---------------------------------------------------------------------------
# Full-pipeline convenience targets (RTL compile if needed + SW compile + run)
# ---------------------------------------------------------------------------
# sim-hello_world / sim-return0: one-shot from scratch.
# verilate is skipped if the simulator binary already exists.
sim-hello_world:
	@test -f $(VLT_SIM) || $(MAKE) verilate
	$(MAKE) run-hello_world

sim-return0:
	@test -f $(VLT_SIM) || $(MAKE) verilate
	$(MAKE) run-return0

# sim-test: compile + run any .c file placed in sim/verilator/tests/.
# Usage: make sim-test TEST=<name>
# Example: cp mytest.c sim/verilator/tests/ && make sim-test TEST=mytest
sim-test:
	@test -n "$(TEST)" || (echo "ERROR: TEST not specified. Usage: make sim-test TEST=<name>"; exit 1)
	@test -f $(VLT_SIM) || $(MAKE) verilate
	$(MAKE) $(VLT_TESTS_BUILD)/$(TEST).elf
	@mkdir -p $(VLT_RESULTS_DIR)/$(TEST)
	cd $(VLT_RESULTS_DIR)/$(TEST) && \
		$(VLT_SIM) +max-cycles=$(MAX_CYCLES) \
			+elf_file=$(VLT_TESTS_BUILD)/$(TEST).elf \
			$(VLT_TESTS_BUILD)/$(TEST).elf \
			2>&1 | tee $(TEST).log

# ---------------------------------------------------------------------------

run:
	@test -n "$(ELF)" || (echo "ERROR: ELF not specified. Use: make run ELF=<path>"; exit 1)
	@test -f $(VLT_SIM) || (echo "ERROR: Simulator binary not found. Run 'make verilate' first."; exit 1)
	@mkdir -p $(VLT_RESULTS_DIR)/custom
	cd $(VLT_RESULTS_DIR)/custom && \
		$(VLT_SIM) +max-cycles=$(MAX_CYCLES) \
			+elf_file=$(abspath $(ELF)) $(abspath $(ELF)) \
			2>&1 | tee $(notdir $(basename $(ELF))).log

run-hello_world: $(VLT_TESTS_BUILD)/hello_world.elf
	@test -f $(VLT_SIM) || (echo "ERROR: Simulator binary not found. Run 'make verilate' first."; exit 1)
	@mkdir -p $(VLT_RESULTS_DIR)/hello_world
	cd $(VLT_RESULTS_DIR)/hello_world && \
		$(VLT_SIM) +max-cycles=$(MAX_CYCLES) \
			+elf_file=$(VLT_TESTS_BUILD)/hello_world.elf \
			$(VLT_TESTS_BUILD)/hello_world.elf \
			2>&1 | tee hello_world.log

run-return0: $(VLT_TESTS_BUILD)/return0.elf
	@test -f $(VLT_SIM) || (echo "ERROR: Simulator binary not found. Run 'make verilate' first."; exit 1)
	@mkdir -p $(VLT_RESULTS_DIR)/return0
	cd $(VLT_RESULTS_DIR)/return0 && \
		$(VLT_SIM) +max-cycles=$(MAX_CYCLES) \
			+elf_file=$(VLT_TESTS_BUILD)/return0.elf \
			$(VLT_TESTS_BUILD)/return0.elf \
			2>&1 | tee return0.log

run-spike-hello_world: $(VLT_TESTS_BUILD)/hello_world.elf
	@mkdir -p $(VLT_RESULTS_DIR)/hello_world
	$(SPIKE) --isa=rv64gc --log-commits \
		$(VLT_TESTS_BUILD)/hello_world.elf \
		2>&1 | tee $(VLT_RESULTS_DIR)/hello_world/hello_world.log.iss

run-spike-return0: $(VLT_TESTS_BUILD)/return0.elf
	@mkdir -p $(VLT_RESULTS_DIR)/return0
	$(SPIKE) --isa=rv64gc --log-commits \
		$(VLT_TESTS_BUILD)/return0.elf \
		2>&1 | tee $(VLT_RESULTS_DIR)/return0/return0.log.iss

#########
# clean #
#########

.PHONY: clean clean-sim clean-verilator clean-tests clean-traces clean-results

clean: clean-sim

clean-sim: clean-verilator clean-tests clean-traces clean-results
	rm -rf $(CVA6_DCLS_GENERATED_SIM_FILES)

clean-verilator:
	rm -rf $(VERILATOR_BUILD_DIR)

clean-tests:
	rm -rf $(VLT_TESTS_BUILD)

clean-traces:
	rm -f $(CVA6_DCLS_ROOT)/trace_hart_*.dasm \
	      $(CVA6_DCLS_ROOT)/trace_rvfi_hart_*.dasm \
	      $(CVA6_DCLS_ROOT)/iti.traces \
	      $(CVA6_DCLS_ROOT)/encaps.traces

clean-results:
	rm -rf $(VLT_RESULTS_DIR)

#######
# All #
#######

.PHONY: all
all: $(CVA6_DCLS_SIM_ALL) $(CVA6_DCLS_HW_ALL)
