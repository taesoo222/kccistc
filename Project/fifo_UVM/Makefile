# VCS + UVM 1.2 Makefile
RTL_DIR   = ./src
TB_DIR    = ./sim
BUILD_DIR = ./build
SIMV      = $(BUILD_DIR)/simv
SRCS      = $(RTL_DIR)/fifo_sv.sv $(TB_DIR)/tb_fifo_uvm.sv

# coverage (compile & run must use the same -cm metrics)
CM_METRICS = line+cond+fsm+tgl+branch+assert
COV_DIR    = coverage.vdb
COV_NAME   = sim1
CM_OPTS    = -cm $(CM_METRICS) -cm_dir $(COV_DIR)

# overridable from command line : make sim VERBOSITY=UVM_LOW FSDB=0
VERBOSITY ?= UVM_HIGH
FSDB      ?= 1

VCS_OPTS  = -full64 -sverilog -debug_access+all -kdb -lca \
            -timescale=1ns/1ps \
            -ntb_opts uvm-1.2 \
            $(CM_OPTS) \
            -o $(SIMV) -l $(BUILD_DIR)/compile.log
ifeq ($(FSDB),1)
VCS_OPTS += +define+FSDB
endif

SIMV_OPTS = $(CM_OPTS) -cm_name $(COV_NAME) \
            +UVM_VERBOSITY=$(VERBOSITY) -l sim.log

all : compile sim

compile :
	mkdir -p $(BUILD_DIR)
	vcs $(VCS_OPTS) $(SRCS)

sim :
	$(SIMV) $(SIMV_OPTS)

# waveform (needs FSDB=1 at compile time)
verdi :
	verdi -dbdir $(SIMV).daidir -ssf wave.fsdb &

# coverage GUI / text report
cov :
	verdi -cov -covdir $(COV_DIR) &

urg :
	urg -dir $(COV_DIR) -format text -report urgReport

clean :
	rm -rf $(BUILD_DIR) csrc $(COV_DIR) urgReport vdCovLog verdiLog novas* \
	       ucli.key vc_hdrs.h vdCov.conf *.fsdb *.log .fsm.sch.verilog.xml \
	       .inter.fsdb* inter.fsdb

.PHONY : all compile sim verdi cov urg clean
