VERILATOR_FLAGS =
# Generate C++ in executable form
VERILATOR_FLAGS += -cc --exe
# Generate makefile dependencies (not shown as complicates the Makefile)
#VERILATOR_FLAGS += -MMD
# Optimize
#VERILATOR_FLAGS += -O2 -x-assign 0
# Warn abount lint issues; may not want this on less solid designs
VERILATOR_FLAGS += -Wall
# Make waveforms
VERILATOR_FLAGS += --trace
# Check SystemVerilog assertions
VERILATOR_FLAGS += --assert
# Generate coverage analysis
VERILATOR_FLAGS += --coverage
# Run Verilator in debug mode
#VERILATOR_FLAGS += --debug
# Add this trace to get a backtrace in gdb
VERILATOR_FLAGS += --gdbbt


build:
	@mkdir -p logs
	verilator $(VERILATOR_FLAGS) --top-module sd_read_stream ../../sdio_project/code/sdio_slave/sd_read_stream.sv ../../sdio_project/code/sdio_slave/sd_crc7.sv sim_main.cpp tests.cpp
	$(MAKE) -j -C obj_dir -f Vsd_read_stream.mk Vsd_read_stream -f ../Makefile_obj

run:
	obj_dir/Vsd_read_stream +trace

clean:
	-rm -rf obj_dir logs

