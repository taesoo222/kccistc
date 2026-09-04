`timescale 1ns / 1ps
`include "uvm_macros.svh"
import uvm_pkg::*;

interface fifo_if (
    input clk
);
    logic       rst_n;
    logic       push;
    logic       pop;
    logic [7:0] wdata;
    logic [7:0] rdata;
    logic       full;
    logic       empty;

    clocking drv_cb @(posedge clk);
        default input #1step output #1;
        output rst_n;
        output push;
        output pop;
        output wdata;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst_n;
        input push;
        input pop;
        input wdata;
        input rdata;
        input full;
        input empty;
    endclocking

    modport drv_mb(clocking drv_cb, input clk);
    modport mon_mb(clocking mon_cb, input clk);

    // 1. property: full/empty must return to their reset value right after rst_n deasserts
    property p_reset_state;
        @(posedge clk) (!rst_n) |=> (full == 1'b0 && empty == 1'b1);
    endproperty

    A_RESET_STATE :
    assert property (p_reset_state)
    else `uvm_error("[ASSERT]", "RESET_ASSERT property p_reset_state!!")

    // 2. property: full and empty can never be asserted at the same time
    property p_full_empty_mutex;
        @(posedge clk) disable iff (!rst_n) !(full && empty);
    endproperty

    A_FULL_EMPTY_MUTEX :
    assert property (p_full_empty_mutex)
    else `uvm_error("[ASSERT]", "MUTEX_ASSERT property p_full_empty_mutex!!")

endinterface

// seq_item
class fifo_seq_item extends uvm_sequence_item;
    rand bit       push;
    rand bit       pop;
    rand bit [7:0] wdata;
    bit            rst_n;
    bit      [7:0] rdata;
    bit            full;
    bit            empty;

    constraint c_op_dist {
        {push, pop} dist {
            2'b10 := 4,  // push only
            2'b01 := 4,  // pop only
            2'b11 := 1,  // push + pop
            2'b00 := 1   // idle
        };
    }

    function new(string name = "fifo_seq_item");
        super.new(name);
    endfunction

    `uvm_object_utils_begin(fifo_seq_item)
        `uvm_field_int(push, UVM_DEFAULT)
        `uvm_field_int(pop, UVM_DEFAULT)
        `uvm_field_int(wdata, UVM_DEFAULT)
        `uvm_field_int(rst_n, UVM_DEFAULT)
        `uvm_field_int(rdata, UVM_DEFAULT)
        `uvm_field_int(full, UVM_DEFAULT)
        `uvm_field_int(empty, UVM_DEFAULT)
    `uvm_object_utils_end

    virtual function string convert2string();
        return $sformatf(
            "rst_n=%b push=%b pop=%b wdata=%3d rdata=%3d full=%b empty=%b",
            rst_n, push, pop, wdata, rdata, full, empty);
    endfunction

endclass

// reset sequence
class fifo_reset_sequence extends uvm_sequence #(fifo_seq_item);
    `uvm_object_utils(fifo_reset_sequence)

    function new(string name = "fifo_reset_seq");
        super.new(name);
    endfunction

    virtual task body();
        fifo_seq_item f_item;
        repeat (5) begin
            f_item = fifo_seq_item::type_id::create("f_item");
            start_item(f_item);
            f_item.rst_n = 0;
            f_item.push  = 0;
            f_item.pop   = 0;
            f_item.wdata = 0;
            finish_item(f_item);
        end
    endtask

endclass

// directed sequence: push repeatedly to drive the fifo into the full corner
class fifo_fill_sequence extends uvm_sequence #(fifo_seq_item);
    `uvm_object_utils(fifo_fill_sequence)

    function new(string name = "fifo_fill_seq");
        super.new(name);
    endfunction

    virtual task body();
        fifo_seq_item f_item;
        repeat (8) begin
            f_item = fifo_seq_item::type_id::create("f_item");
            start_item(f_item);
            if (!f_item.randomize() with {push == 1; pop == 0;}) begin
                `uvm_fatal(get_type_name(), "fill randomize fail")
            end
            f_item.rst_n = 1;
            finish_item(f_item);
        end
    endtask

endclass

// directed sequence: pop repeatedly to drive the fifo into the empty corner
class fifo_drain_sequence extends uvm_sequence #(fifo_seq_item);
    `uvm_object_utils(fifo_drain_sequence)

    function new(string name = "fifo_drain_seq");
        super.new(name);
    endfunction

    virtual task body();
        fifo_seq_item f_item;
        repeat (8) begin
            f_item = fifo_seq_item::type_id::create("f_item");
            start_item(f_item);
            if (!f_item.randomize() with {push == 0; pop == 1;}) begin
                `uvm_fatal(get_type_name(), "drain randomize fail")
            end
            f_item.rst_n = 1;
            finish_item(f_item);
        end
    endtask

endclass

// random sequence for the main regression
class fifo_random_sequence extends uvm_sequence #(fifo_seq_item);
    `uvm_object_utils(fifo_random_sequence)

    function new(string name = "fifo_random_seq");
        super.new(name);
    endfunction

    virtual task body();
        fifo_seq_item f_item;
        repeat (300) begin
            f_item = fifo_seq_item::type_id::create("f_item");
            start_item(f_item);
            if (!f_item.randomize()) begin
                `uvm_fatal(get_type_name(), "random randomize fail")
            end
            f_item.rst_n = 1;
            finish_item(f_item);
        end
    endtask

endclass

// driver
class fifo_driver extends uvm_driver #(fifo_seq_item);
    `uvm_component_utils(fifo_driver)
    virtual fifo_if f_if;
    fifo_seq_item   f_item;

    function new(string name = "fifo_drv", uvm_component c = null);
        super.new(name, c);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual fifo_if)::get(
                this, "", "f_if", f_if
            )) begin
            `uvm_fatal(get_name(), "unable to access fifo interface")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        forever begin
            seq_item_port.get_next_item(f_item);
            @(f_if.drv_cb);
            f_if.drv_cb.rst_n <= f_item.rst_n;
            f_if.drv_cb.push  <= f_item.push;
            f_if.drv_cb.pop   <= f_item.pop;
            f_if.drv_cb.wdata <= f_item.wdata;
            seq_item_port.item_done();
        end
    endtask

endclass

// monitor
class fifo_monitor extends uvm_monitor;
    `uvm_component_utils(fifo_monitor)

    virtual fifo_if f_if;
    fifo_seq_item f_item;
    uvm_analysis_port #(fifo_seq_item) send;

    function new(string name = "fifo_mon", uvm_component c = null);
        super.new(name, c);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual fifo_if)::get(
                this, "", "f_if", f_if
            )) begin
            `uvm_fatal(get_name(), "unable to access fifo interface")
        end
        send = new("send", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        forever begin
            f_item = fifo_seq_item::type_id::create("fifo_seq_item", this);
            @(f_if.mon_cb);
            f_item.rst_n = f_if.mon_cb.rst_n;
            f_item.push  = f_if.mon_cb.push;
            f_item.pop   = f_if.mon_cb.pop;
            f_item.wdata = f_if.mon_cb.wdata;
            f_item.rdata = f_if.mon_cb.rdata;
            f_item.full  = f_if.mon_cb.full;
            f_item.empty = f_if.mon_cb.empty;

            send.write(f_item);
        end
    endtask
endclass

// agent
class fifo_agent extends uvm_agent;
    `uvm_component_utils(fifo_agent)
    fifo_driver                    drv;
    fifo_monitor                   mon;
    uvm_sequencer #(fifo_seq_item) sqr;

    function new(string name = "fifo_agt", uvm_component c = null);
        super.new(name, c);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        drv = fifo_driver::type_id::create("drv", this);
        mon = fifo_monitor::type_id::create("mon", this);
        sqr = uvm_sequencer#(fifo_seq_item)::type_id::create("sqr", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction

endclass

// scoreboard : cycle-accurate reference model that mirrors fifo_control_unit's case logic
class fifo_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(fifo_scoreboard)
    uvm_analysis_imp #(fifo_seq_item, fifo_scoreboard) recv;

    // must match fifo_sv #(.WIDTH(2)) instantiated in tb_fifo_uvm
    localparam int DEPTH = 4;

    bit [7:0] model_q[$];
    bit pred_full = 0;
    bit pred_empty = 1;

    int flag_pass_cnt, flag_fail_cnt = 0;
    int data_pass_cnt, data_fail_cnt = 0;
    int skip_cnt = 0;

    function new(string name = "fifo_scb", uvm_component c = null);
        super.new(name, c);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        recv = new("recv", this);
    endfunction

    virtual function void write(fifo_seq_item f_item);
        `uvm_info(get_type_name(), f_item.convert2string(), UVM_HIGH)

        if (!f_item.rst_n) begin
            model_q.delete();
            pred_full  = 0;
            pred_empty = 1;
            skip_cnt++;
            return;
        end

        // 1. check the flags sampled this cycle against last cycle's prediction
        if (f_item.full === pred_full && f_item.empty === pred_empty) begin
            flag_pass_cnt++;
        end else begin
            `uvm_error(get_type_name(), $sformatf(
                       "FLAG FAIL !! expect full=%b empty=%b, got full=%b empty=%b",
                       pred_full, pred_empty, f_item.full, f_item.empty))
            flag_fail_cnt++;
        end

        // 2. replay fifo_control_unit's case({push,pop}) on the golden model
        case ({
            f_item.push, f_item.pop
        })
            2'b00: ;  // no change

            2'b01: begin  // pop only
                if (!pred_empty) check_and_pop(f_item.rdata);
            end

            2'b10: begin  // push only
                if (!pred_full) begin
                    model_q.push_back(f_item.wdata);
                    pred_empty = 0;
                    if (model_q.size() == DEPTH) pred_full = 1;
                end
            end

            2'b11: begin  // push + pop
                if (pred_full) begin
                    check_and_pop(f_item.rdata);
                end else if (pred_empty) begin
                    model_q.push_back(f_item.wdata);
                    pred_empty = 0;
                end else begin
                    check_and_pop(f_item.rdata);
                    model_q.push_back(f_item.wdata);
                end
            end
        endcase
    endfunction

    // pops the model queue and checks the popped value against the sampled rdata
    virtual function void check_and_pop(bit [7:0] rdata);
        bit [7:0] exp_data = model_q.pop_front();
        if (exp_data === rdata) begin
            data_pass_cnt++;
        end else begin
            `uvm_error(get_type_name(), $sformatf(
                       "DATA FAIL !! expect=%3d, rdata=%3d", exp_data, rdata))
            data_fail_cnt++;
        end
        pred_full = 0;
        if (model_q.size() == 0) pred_empty = 1;
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SCB", $sformatf("\n            "), UVM_NONE)
        `uvm_info("SCB", $sformatf("Result Flag Pass:%d", flag_pass_cnt), UVM_NONE)
        `uvm_info("SCB", $sformatf("Result Flag Fail:%d", flag_fail_cnt), UVM_NONE)
        `uvm_info("SCB", $sformatf("Result Data Pass:%d", data_pass_cnt), UVM_NONE)
        `uvm_info("SCB", $sformatf("Result Data Fail:%d", data_fail_cnt), UVM_NONE)
        `uvm_info("SCB", $sformatf("Result Skip:%d", skip_cnt), UVM_NONE)
    endfunction

endclass

// coverage
class fifo_coverage extends uvm_subscriber #(fifo_seq_item);
    `uvm_component_utils(fifo_coverage)

    fifo_seq_item f_item;

    covergroup fifo_cg;
        option.per_instance = 1;

        cp_push: coverpoint f_item.push;
        cp_pop: coverpoint f_item.pop;
        cp_full: coverpoint f_item.full;
        cp_empty: coverpoint f_item.empty;

        cx_push_full: cross cp_push, cp_full;
        cx_pop_empty: cross cp_pop, cp_empty;
        cx_push_pop: cross cp_push, cp_pop;
    endgroup

    function new(string name = "fifo_cov", uvm_component c = null);
        super.new(name, c);
        fifo_cg = new();
    endfunction

    virtual function void write(fifo_seq_item t_item);
        if (!t_item.rst_n) return;
        f_item = t_item;
        fifo_cg.sample();
    endfunction

    virtual function void report_phase(uvm_phase phase);
        `uvm_info("COV", $sformatf("\n*** Coverage Report ***"), UVM_NONE)
        `uvm_info("COV", $sformatf(
                  "** Overall        = %.1f %% **", fifo_cg.get_coverage()),
                  UVM_NONE)
        `uvm_info("COV", $sformatf(
                  "** push/full      = %.1f %% **",
                  fifo_cg.cx_push_full.get_coverage()), UVM_NONE)
        `uvm_info("COV", $sformatf(
                  "** pop/empty      = %.1f %% **",
                  fifo_cg.cx_pop_empty.get_coverage()), UVM_NONE)
        `uvm_info("COV", $sformatf(
                  "** push/pop       = %.1f %% **",
                  fifo_cg.cx_push_pop.get_coverage()), UVM_NONE)
        `uvm_info("COV", $sformatf("\n***********************"), UVM_NONE)
    endfunction

endclass

// environment
class fifo_environment extends uvm_env;
    `uvm_component_utils(fifo_environment)
    fifo_agent      agt;
    fifo_scoreboard scb;
    fifo_coverage   cov;

    function new(string name = "fifo_env", uvm_component c = null);
        super.new(name, c);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agt = fifo_agent::type_id::create("agt", this);
        scb = fifo_scoreboard::type_id::create("scb", this);
        cov = fifo_coverage::type_id::create("cov", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agt.mon.send.connect(scb.recv);
        agt.mon.send.connect(cov.analysis_export);
    endfunction

endclass

// test
class fifo_test extends uvm_test;
    `uvm_component_utils(fifo_test)
    fifo_reset_sequence  seq_reset;
    fifo_fill_sequence   seq_fill;
    fifo_drain_sequence  seq_drain;
    fifo_random_sequence seq_random;
    fifo_environment     env;

    function new(string name = "fifo_test", uvm_component c = null);
        super.new(name, c);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        seq_reset  = fifo_reset_sequence::type_id::create("seq_reset", this);
        seq_fill   = fifo_fill_sequence::type_id::create("seq_fill", this);
        seq_drain  = fifo_drain_sequence::type_id::create("seq_drain", this);
        seq_random = fifo_random_sequence::type_id::create("seq_random", this);
        env        = fifo_environment::type_id::create("env", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);

        phase.raise_objection(this);
        seq_reset.start(env.agt.sqr);
        phase.drop_objection(this);

        // directed corner cases first: force full, then force empty
        phase.raise_objection(this);
        seq_fill.start(env.agt.sqr);
        seq_drain.start(env.agt.sqr);
        phase.drop_objection(this);

        // broad random regression
        phase.raise_objection(this);
        seq_random.start(env.agt.sqr);
        repeat (2) @(posedge env.agt.drv.f_if.clk);
        phase.drop_objection(this);
    endtask

endclass

module tb_fifo_uvm ();

    localparam WIDTH = 2;

    logic clk = 0;
    always #5 clk = ~clk;

    fifo_if f_if (clk);

    fifo_sv #(
        .WIDTH(WIDTH)
    ) dut (
        .clk  (clk),
        .rst_n(f_if.rst_n),
        .push (f_if.push),
        .pop  (f_if.pop),
        .wdata(f_if.wdata),
        .rdata(f_if.rdata),
        .full (f_if.full),
        .empty(f_if.empty)
    );

    initial begin
        // Vivado xsim wave dump (VCD)
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_fifo_uvm);
    end

    initial begin
        uvm_config_db#(virtual fifo_if)::set(null, "*", "f_if", f_if);
        run_test("fifo_test");
    end

endmodule
