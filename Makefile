CXX ?= g++
CXXFLAGS ?= -std=c++20 -O2 -Wall -Wextra -Werror -pedantic
BUILD_DIR := build
MODEL_TEST := $(BUILD_DIR)/test_rv32_model
VERILATOR_WARN_FLAGS := -Wall --Wno-fatal --Wno-UNUSEDSIGNAL --Wno-UNUSEDPARAM

.PHONY: all model-test rtl-lint rtl-test clean

all: model-test

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(MODEL_TEST): cpp/rv32_model.cpp tests/test_rv32_model.cpp hpp/rv32_model.hpp | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) -Ihpp cpp/rv32_model.cpp tests/test_rv32_model.cpp -o $@

model-test: $(MODEL_TEST)
	$(MODEL_TEST)

rtl-lint:
	verilator --lint-only $(VERILATOR_WARN_FLAGS) --top-module rv32_simple_soc -Irtl \
		rtl/rv32_pkg.sv rtl/rv32_frontend.sv rtl/rv32_decode.sv \
		rtl/rv32_rename.sv rtl/rv32_rob.sv rtl/rv32_int_rs.sv \
		rtl/rv32_alu_branch.sv rtl/rv32_lsq.sv rtl/rv32_lsu.sv \
		rtl/rv32_writeback.sv rtl/rv32_ooo_core.sv rtl/rv32_simple_soc.sv

rtl-test:
	verilator --binary --timing $(VERILATOR_WARN_FLAGS) --Wno-BLKSEQ --Wno-SYNCASYNCNET -Irtl \
		rtl/rv32_pkg.sv rtl/rv32_frontend.sv rtl/rv32_decode.sv \
		rtl/rv32_rename.sv rtl/rv32_rob.sv rtl/rv32_int_rs.sv \
		rtl/rv32_alu_branch.sv rtl/rv32_lsq.sv rtl/rv32_lsu.sv \
		rtl/rv32_writeback.sv rtl/rv32_ooo_core.sv rtl/rv32_simple_soc.sv \
		tests/tb_rv32_ooo_core.sv --top-module tb_rv32_ooo_core -Mdir $(BUILD_DIR)/obj_rtl
	$(BUILD_DIR)/obj_rtl/Vtb_rv32_ooo_core

clean:
	rm -rf $(BUILD_DIR)
