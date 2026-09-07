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

    property p_full_empty_exclusive;
        @(posedge clk) disable iff (!rst_n) !(full && empty);
    endproperty

    A_FULL_EMPTY_EXCLUSIVE :
    assert property (p_full_empty_exclusive)
    else `uvm_error("[ASSERT]", "full and empty asserted at the same time!!")

endinterface

// seq item
// transaction
class fifo_seq_item extends uvm_sequence_item;
    //DRV
    rand bit push;
    rand bit pop;
    rand bit [7:0] wdata;
    rand bit rst_n;
    //MON
    bit [7:0] rdata;
    bit full;
    bit empty;

    constraint c_op_dist {
        {
            push, pop
        } dist {
            2'b10 := 4,
            2'b01 := 4,
            2'b11 := 1,
            2'b00 := 1
        };
    }

    constraint c_rst_dist {
        rst_n dist {
            1 := 98,
            0 := 2
        };
    }

    `uvm_object_utils_begin(fifo_seq_item)
        `uvm_field_int(rst_n, UVM_DEFAULT)
        `uvm_field_int(push, UVM_DEFAULT)
        `uvm_field_int(pop, UVM_DEFAULT)
        `uvm_field_int(wdata, UVM_DEFAULT)
        `uvm_field_int(rdata, UVM_DEFAULT)
        `uvm_field_int(full, UVM_DEFAULT)
        `uvm_field_int(empty, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "seq_item");
        super.new(name);
    endfunction

    function string c2string(string name);

        return $sformatf(
            "[%s] push = %d, pop = %d, wdata = %d, rdata = %d, full = %d, empty = %d",
            name,
            push,
            pop,
            wdata,
            rdata,
            full,
            empty
        );
    endfunction
endclass

// sequence
// #1 reset
class fifo_reset_sequence extends uvm_sequence #(fifo_seq_item);
    `uvm_object_utils(fifo_reset_sequence)
    fifo_seq_item f_item;

    function new(string name = "reset_seq");
        super.new(name);
    endfunction

    task body();
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

// seqeunce
// #2 edge case full only
class fifo_full_sequence extends uvm_sequence #(fifo_seq_item);
    `uvm_object_utils(fifo_full_sequence)
    fifo_seq_item f_item;

    function new(string name = "full_seq");
        super.new(name);
    endfunction

    task body();
        // why ? repeat 32 ram size 16bit x 2
        repeat (32) begin
            f_item = fifo_seq_item::type_id::create("f_item");
            start_item(f_item);
            if (!f_item.randomize() with {
                    push == 1;
                    pop == 0;
                })
                `uvm_fatal(get_type_name(), "randomize fail");
            f_item.rst_n = 1;
            finish_item(f_item);
        end
    endtask
endclass

// sequnece
// #3 edge case empty only
class fifo_empty_sequence extends uvm_sequence #(fifo_seq_item);
    `uvm_object_utils(fifo_empty_sequence)
    fifo_seq_item f_item;

    function new(string name = "empty_seq");
        super.new(name);
    endfunction

    task body();
        repeat (32) begin
            f_item = fifo_seq_item::type_id::create("f_item");
            start_item(f_item);
            if (!f_item.randomize() with {
                    push == 0;
                    pop == 1;
                })
                `uvm_fatal(get_type_name(), "randomize fail");
            f_item.rst_n = 1;
            finish_item(f_item);
        end
    endtask
endclass

// sequence
// #4 concurrent (edge_full -> concurrent , edge_empty -> concurrent)
class fifo_concurrent_sequence extends uvm_sequence #(fifo_seq_item);
    `uvm_object_utils(fifo_concurrent_sequence)
    fifo_seq_item f_item;

    function new(string name = "concurrent_seq");
        super.new(name);
    endfunction

    task body();
        repeat (5) begin
            f_item = fifo_seq_item::type_id::create("f_item");
            start_item(f_item);
            if (!f_item.randomize() with {
                    push == 1;
                    pop == 1;
                })
                `uvm_fatal(get_type_name(), "randomize fail");
            f_item.rst_n = 1;
            finish_item(f_item);
        end
    endtask
endclass

// seqeunce
// #5 nomal
class fifo_normal_sequence extends uvm_sequence #(fifo_seq_item);
    `uvm_object_utils(fifo_normal_sequence)
    fifo_seq_item f_item;

    function new(string name = "normal_seq");
        super.new(name);
    endfunction

    task body();
        repeat (2000) begin
            f_item = fifo_seq_item::type_id::create("f_item");
            start_item(f_item);
            if (!f_item.randomize())
                `uvm_fatal(get_type_name(), "randomize fail");
            f_item.rst_n = 1;
            finish_item(f_item);
        end
    endtask
endclass

// driver
class fifo_driver extends uvm_driver #(fifo_seq_item);
    `uvm_component_utils(fifo_driver)

    virtual fifo_if f_if;
    fifo_seq_item f_item;
    int rst_drive_cnt;

    function new(string name = "drv", uvm_component c = null);
        super.new(name, c);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual fifo_if)::get(this, "", "f_if", f_if))
            `uvm_fatal("drv", "build phase : can't access virtual interface")
    endfunction

    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        // drv_cb output skew always lands one edge after it's issued, so
        // the very first posedge would sample stale X on the interface.
        // Drive the idle/reset values straight onto the pins (bypassing
        // the clocking block) before that first edge so the monitor's
        // first sample already matches what the sequencer intends to
        // drive.
        f_if.rst_n = 1'b0;
        f_if.push  = 1'b0;
        f_if.pop   = 1'b0;
        f_if.wdata = 8'b0;
        forever begin
            seq_item_port.get_next_item(f_item);
            if (f_item.rst_n == 0) rst_drive_cnt++;
            @(f_if.drv_cb);
            f_if.drv_cb.rst_n <= f_item.rst_n;
            f_if.drv_cb.push  <= f_item.push;
            f_if.drv_cb.pop   <= f_item.pop;
            f_if.drv_cb.wdata <= f_item.wdata;
            seq_item_port.item_done();
        end
    endtask

    virtual function void report_phase(uvm_phase phase);
        `uvm_info(get_type_name(), $sformatf(
                  "\n**************************************************************************Total rst_n=0 driven: %d",
                  rst_drive_cnt
                  ), UVM_NONE)
    endfunction
endclass

// monitor
class fifo_monitor extends uvm_monitor;
    `uvm_component_utils(fifo_monitor)
    uvm_analysis_port #(fifo_seq_item) send;
    virtual fifo_if f_if;
    fifo_seq_item f_item;

    function new(string name = "mon", uvm_component c = null);
        super.new(name, c);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual fifo_if)::get(this, "", "f_if", f_if))
            `uvm_fatal("mon", "build_phase : can't access virtual interface");

        send = new("WRITE", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        forever begin
            f_item = fifo_seq_item::type_id::create("f_item", this);

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
    fifo_driver                    fifo_drv;
    fifo_monitor                   fifo_mon;
    uvm_sequencer #(fifo_seq_item) fifo_sqr;

    function new(string name = "agt", uvm_component c = null);
        super.new(name, c);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        fifo_drv = fifo_driver::type_id::create("drv", this);
        fifo_mon = fifo_monitor::type_id::create("mon", this);
        fifo_sqr = uvm_sequencer#(fifo_seq_item)::type_id::create("sqr", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        fifo_drv.seq_item_port.connect(fifo_sqr.seq_item_export);
    endfunction
endclass

// scoreboard
class fifo_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(fifo_scoreboard)
    uvm_analysis_imp #(fifo_seq_item, fifo_scoreboard) recv;

    // reference model
    bit [7:0] ram_buffer[$];
    bit pred_full;
    bit pred_empty;

    // count vari
    int flag_pass_cnt, flag_fail_cnt;
    int data_pass_cnt, data_fail_cnt;
    int skip_cnt;

    function new(string name = "scb", uvm_component c = null);
        super.new(name, c);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        recv = new("READ", this);
    endfunction

    virtual function void write(fifo_seq_item f_item);
        `uvm_info(get_type_name(), f_item.c2string(get_type_name()), UVM_HIGH)

        // rst -> compare X
        if (f_item.rst_n !== 1'b1) begin
            `uvm_info(get_type_name(), $sformatf("TO skip : fifo is X"),
                      UVM_NONE)
            ram_buffer.delete();
            pred_full  = 0;
            pred_empty = 1;
            skip_cnt++;
            return;
        end

        // full flag
        if (f_item.full === pred_full) begin
            `uvm_info(get_type_name(),
                      $sformatf(
                          "Pass !! (full match) expect_full: %d, dut_full: %d",
                          pred_full, f_item.full), UVM_HIGH)
            flag_pass_cnt++;
        end else begin
            `uvm_error("SCB_FLAG", $sformatf(
                       "Fail !! (full mismatch) expect_full: %d, dut_full: %d",
                       pred_full,
                       f_item.full
                       ))
            flag_fail_cnt++;
        end

        // empty flag
        if (f_item.empty === pred_empty) begin
            `uvm_info(
                get_type_name(),
                $sformatf(
                    "Pass !! (empty match) expect_empty: %d, dut_empty: %d",
                    pred_empty, f_item.empty), UVM_HIGH)
            flag_pass_cnt++;
        end else begin
            `uvm_error("SCB_FLAG", $sformatf(
                       "Fail !! (empty mismatch) expect_empty: %d, dut_empty: %d",
                       pred_empty,
                       f_item.empty
                       ))
            flag_fail_cnt++;
        end

        // data
        if (!pred_empty) begin
            if (f_item.rdata === ram_buffer[0]) begin
                `uvm_info(
                    get_type_name(),
                    $sformatf(
                        "Pass !! (rdata match) expect_rdata: %d, dut_rdata: %d",
                        ram_buffer[0], f_item.rdata), UVM_HIGH)
                data_pass_cnt++;
            end else begin
                `uvm_error("SCB_DATA", $sformatf(
                           "Fail !! (rdata mismatch) expect_rdata: %d, dut_rdata: %d",
                           ram_buffer[0],
                           f_item.rdata
                           ))
                data_fail_cnt++;
            end
        end

        // using queue
        case ({
            f_item.push, f_item.pop
        })
            2'b00: ;
            2'b01:
            if (!pred_empty) begin
                ram_buffer.pop_front();
                pred_full = 0;
                if (ram_buffer.size() == 0) pred_empty = 1;
            end
            2'b10:
            if (!pred_full) begin
                ram_buffer.push_back(f_item.wdata);
                pred_empty = 0;
                if (ram_buffer.size() == 16) pred_full = 1;
            end
            2'b11: begin
                if (pred_full) begin
                    ram_buffer.pop_front();
                    pred_full = 0;
                end else if (pred_empty) begin
                    ram_buffer.push_back(f_item.wdata);
                    pred_empty = 0;
                end else begin
                    ram_buffer.pop_front();
                    ram_buffer.push_back(f_item.wdata);
                end
            end
        endcase
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SCB", $sformatf("___________________________________"),
                  UVM_NONE)
        `uvm_info("SCB", $sformatf("Result Flag Pass:%d", flag_pass_cnt),
                  UVM_NONE)
        `uvm_info("SCB", $sformatf("Result Flag Fail:%d", flag_fail_cnt),
                  UVM_NONE)
        `uvm_info("SCB", $sformatf("Result Data Pass:%d", data_pass_cnt),
                  UVM_NONE)
        `uvm_info("SCB", $sformatf("Result Data Fail:%d", data_fail_cnt),
                  UVM_NONE)
        `uvm_info("SCB", $sformatf("Result Skip:%d", skip_cnt), UVM_NONE)
        `uvm_info("SCB", $sformatf("___________________________________"),
                  UVM_NONE)
    endfunction
endclass

// coverage
class fifo_coverage extends uvm_subscriber #(fifo_seq_item);
    `uvm_component_utils(fifo_coverage)
    fifo_seq_item f_item;

    covergroup fifo_cg;
        option.per_instance = 1;

        cp_op: coverpoint {
            f_item.push, f_item.pop
        } {  // 4
            bins idle = {2'b00};
            bins push_only = {2'b10};
            bins pop_only = {2'b01};
            bins concurrent = {2'b11};
        }
        cp_full: coverpoint f_item.full {bins full[] = {[0 : 1]};}  // 2
        cp_empty: coverpoint f_item.empty {bins empty[] = {[0 : 1]};}  // 2

        cp_wdata: coverpoint f_item.wdata iff (f_item.push == 1) {
            bins range_0_to_255[] = {[0 : 255]};
        }
        cp_rdata: coverpoint f_item.rdata iff (f_item.pop == 1 && f_item.empty == 0) {
            bins range_0_to_255[] = {[0 : 255]};
        }

        cx_op_state: cross cp_op, cp_full, cp_empty{
            ignore_bins impossible = binsof(cp_full) intersect {1} &&
                                      binsof(cp_empty) intersect {
                1
            };
        }
    endgroup

    function new(string name = "cov", uvm_component c = null);
        super.new(name, c);
        fifo_cg = new();
    endfunction

    virtual function void write(fifo_seq_item t);
        f_item = t;
        fifo_cg.sample();
    endfunction

    virtual function void report_phase(uvm_phase phase);
        `uvm_info("COV", $sformatf("\n*** Coverage Report ***"), UVM_NONE);
        `uvm_info("COV", $sformatf(
                  "** Overall     = %.1f %% **", fifo_cg.get_coverage()),
                  UVM_NONE);
        `uvm_info("COV", $sformatf(
                  "** op          = %.1f %% **", fifo_cg.cp_op.get_coverage()),
                  UVM_NONE);
        `uvm_info("COV", $sformatf(
                  "** wdata       = %.1f %% **", fifo_cg.cp_wdata.get_coverage()
                  ), UVM_NONE);
        `uvm_info("COV", $sformatf(
                  "** rdata       = %.1f %% **", fifo_cg.cp_rdata.get_coverage()
                  ), UVM_NONE);
        `uvm_info(
            "COV", $sformatf(
            "** cx_op_state = %.1f %% **", fifo_cg.cx_op_state.get_coverage()),
            UVM_NONE);
    endfunction
endclass

// environment
class fifo_environment extends uvm_env;
    `uvm_component_utils(fifo_environment)
    fifo_agent fifo_agt;
    fifo_scoreboard fifo_scb;
    fifo_coverage fifo_cov;

    function new(string name = "env", uvm_component c = null);
        super.new(name, c);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        fifo_agt = fifo_agent::type_id::create("agt", this);
        fifo_scb = fifo_scoreboard::type_id::create("scb", this);
        fifo_cov = fifo_coverage::type_id::create("cov", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        fifo_agt.fifo_mon.send.connect(fifo_scb.recv);
        fifo_agt.fifo_mon.send.connect(fifo_cov.analysis_export);
    endfunction
endclass

// test
class fifo_test extends uvm_test;
    `uvm_component_utils(fifo_test)

    virtual fifo_if          f_if;
    fifo_environment         fifo_env;
    fifo_reset_sequence      reset_seq;
    fifo_full_sequence       full_seq;
    fifo_empty_sequence      empty_seq;
    fifo_concurrent_sequence concurrent_seq;
    fifo_normal_sequence     normal_seq;

    function new(string name = "fifo_test", uvm_component c = null);
        super.new(name, c);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual fifo_if)::get(this, "", "f_if", f_if))
            `uvm_fatal(get_type_name(), "can't get f_if")
        fifo_env = fifo_environment::type_id::create("env", this);
        reset_seq = fifo_reset_sequence::type_id::create("reset_seq", this);
        full_seq = fifo_full_sequence::type_id::create("full_seq", this);
        empty_seq = fifo_empty_sequence::type_id::create("empty_seq", this);
        concurrent_seq =
            fifo_concurrent_sequence::type_id::create("concurrent_seq", this);
        normal_seq = fifo_normal_sequence::type_id::create("normal_seq", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        phase.raise_objection(this);
        //////////////////////////////////////////////
        // #1 reset
        `uvm_info("run_phase", "Reset start", UVM_LOW)
        reset_seq.start(fifo_env.fifo_agt.fifo_sqr);
        `uvm_info("run_phase", "Reset end", UVM_LOW)


        // #2 full
        `uvm_info("run_phase", "full_seq start", UVM_LOW)
        full_seq.start(fifo_env.fifo_agt.fifo_sqr);
        concurrent_seq.start(fifo_env.fifo_agt.fifo_sqr);
        `uvm_info("run_phase", "full_seq end", UVM_LOW)

        // #3 empty
        `uvm_info("run_phase", "empty_seq start", UVM_LOW)
        empty_seq.start(fifo_env.fifo_agt.fifo_sqr);
        concurrent_seq.start(fifo_env.fifo_agt.fifo_sqr);
        `uvm_info("run_phase", "empty_seq end", UVM_LOW)

        // //#4 working reset
        // `uvm_info("run_phase", "working reset test start", UVM_LOW)
        // full_seq.start(fifo_env.fifo_agt.fifo_sqr);
        // reset_seq.start(fifo_env.fifo_agt.fifo_sqr);
        // `uvm_info("run_phase", "working reset test end", UVM_LOW)

        // #5 normal
        `uvm_info("run_phase", "normal_seq started", UVM_LOW)
        normal_seq.start(fifo_env.fifo_agt.fifo_sqr);
        `uvm_info("run_phase", "normal_seq end", UVM_LOW)
        //////////////////////////////////////////////
        repeat (2) @(f_if.mon_cb);
        phase.drop_objection(this);
    endtask
endclass

module tb_fifo_uvm ();
    localparam WIDTH = 4;

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
        $fsdbDumpfile("wave.fsdb");
        $fsdbDumpvars(0, tb_fifo_uvm);
    end

    initial begin
        uvm_config_db#(virtual fifo_if)::set(null, "*", "f_if", f_if);
        run_test("fifo_test");
    end
endmodule




// interface fifo_if (
//     input clk
// );
//     logic       rst_n;
//     logic       push;
//     logic       pop;
//     logic [7:0] wdata;
//     logic [7:0] rdata;
//     logic       full;
//     logic       empty;
// endinterface

// module tb_fifo_uvm ();
//     localparam WIDTH = 4;

//     logic clk = 0;
//     always #5 clk = ~clk;

//     fifo_if f_if (clk);

//     fifo_sv #(
//         .WIDTH(WIDTH)
//     ) dut (
//         .clk  (clk),
//         .rst_n(f_if.rst_n),
//         .push (f_if.push),
//         .pop  (f_if.pop),
//         .wdata(f_if.wdata),
//         .rdata(f_if.rdata),
//         .full (f_if.full),
//         .empty(f_if.empty)
//     );

//     initial begin
//         // reset
//         f_if.rst_n = 0;
//         f_if.push  = 0;
//         f_if.pop   = 0;
//         f_if.wdata = 0;
//         repeat (2) @(posedge clk);
//         f_if.rst_n = 1;
//         @(posedge clk);

//         // full set
//         for (int i = 0; i < 16; i++) begin
//             f_if.push  = 1;
//             f_if.pop   = 0;
//             f_if.wdata = i;
//             @(posedge clk);
//         end
//         f_if.push = 0;
//         @(posedge clk);
//         @(posedge clk);

//         // pop_only && full=1
//         f_if.push = 0;
//         f_if.pop  = 1;
//         @(posedge clk);
//         f_if.pop = 0;

//         repeat (50) @(posedge clk);
//         $finish;
//     end

//     initial begin
//         $fsdbDumpfile("wave.fsdb");
//         $fsdbDumpvars(0, tb_fifo_uvm);
//     end
// endmodule

