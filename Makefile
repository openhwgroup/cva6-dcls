BENDER ?= bender

VLOG_ARGS  ?= -timescale 1ns/1ps
VLT_ARGS   ?=

# Target configuration for CVA6
BENDER_CVA6_TARGET ?= -t cv64a6_imafdchsclic_sv39_wb
# Common targets for RTL simulation
BENDER_CVA6_DCLS_RTL_TARGETS ?= -t rtl $(BENDER_CVA6_TARGET)

# Define useful paths
CVA6_DCLS_ROOT ?= $(shell realpath -eP .)
CVA6_ROOT      ?= $(shell $(BENDER) path cva6)

################
# Dependencies #
################

BENDER_ROOT ?= $(CVA6_DCLS_ROOT)/.bender

# Ensure both Bender dependencies and (essential) submodules are checked out
$(BENDER_ROOT)/.cva6_dcls_deps:
	$(BENDER) checkout
	cd $(CVA6_DCLS_ROOT) && git submodule update --init --recursive
	@touch $@

# Make sure dependencies are more up-to-date than any targets run
ifeq ($(shell test -f $(BENDER_ROOT)/.cva6_dcls_deps && echo 1),)
-include $(BENDER_ROOT)/.cva6_dcls_deps
endif

# Running this target will reset dependencies (without updating the checked-in Bender.lock)
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
	$(BENDER) script verilator -t sim -t test $(BENDER_CVA6_DCLS_RTL_TARGETS) --vlt-args="$(VLT_ARGS)" > $@

CVA6_DCLS_SIM_ALL += $(CVA6_DCLS_ROOT)/target/sim/vsim/compile.dcls.tcl
CVA6_DCLS_SIM_ALL += $(CVA6_DCLS_ROOT)/target/sim/vlt/compile.dcls.vlt

#######
# All #
#######

all: $(CVA6_DCLS_SIM_ALL) $(CVA6_DCLS_HW_ALL)
