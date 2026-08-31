`timescale 1ns / 1ps

`include "uvm_macros.svh"
import uvm_pkg::*;

interface ram_if (
    input clk
);

    logic       we;
    logic [7:0] addr;
    logic [7:0] wdata;
    logic [7:0] rdata;

endinterface

// seq_item
class ram_seq_item extends uvm_sequence_item;


    rand logic       we;
    rand logic [7:0] addr;
    rand logic [7:0] wdata;
    logic      [7:0] rdata;



    constraint c_we_ {
        we dist {
            0 := 1,
            1 := 1
        };
    }

    `uvm_object_utils_begin(ram_seq_item)
        `uvm_field_int(we, UVM_DEFAULT)
        `uvm_field_int(addr, UVM_DEFAULT)
        `uvm_field_int(wdata, UVM_DEFAULT)
        `uvm_field_int(rdata, UVM_DEFAULT)
    `uvm_object_utils_end


    function new(string name = "ram_seq_item");
        super.new(name);
    endfunction

    function string c2string(string name);
        return $sformatf(
            "[%s] we = %d, addr = %d, wdata = %d, rdata = %d",
            name,
            we,
            addr,
            wdata,
            rdata
        );
    endfunction
endclass

// ram_sequence
class ram_sequence extends uvm_sequence #(ram_seq_item);
    `uvm_object_utils(ram_sequence)
    ram_seq_item r_item;


    function new(string name = "ram_seq");
        super.new(name);
    endfunction

    virtual task body();

        ram_seq_item r_item;

        repeat (10) begin
            r_item = ram_seq_item::type_id::create("ram_seq_item");

            start_item(r_item);
            if (!r_item.randomize()) `uvm_fatal("ram_seq", "randomized fail");

            finish_item(r_item);
            // `uvm_info("ram_seq", r_item.c2string("SEQ"), UVM_HIGH);
        end
    endtask
endclass


// ram_driver
class ram_driver extends uvm_driver #(ram_seq_item);
    `uvm_component_utils(ram_driver)

    virtual ram_if r_if;
    ram_seq_item   r_item;

    function new(string name = "ram_drv", uvm_component c = null);
        super.new(name, c);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual ram_if)::get(this, "", "r_if", r_if))
            `uvm_fatal("ram_drv",
                       "drv build phase : can't access virtual interface")
    endfunction

    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        forever begin
            seq_item_port.get_next_item(r_item);

            // drive
            @(negedge r_if.clk);
            r_if.we    <= r_item.we;
            r_if.addr  <= r_item.addr;
            r_if.wdata <= r_item.wdata;


            seq_item_port.item_done();
        end

    endtask

endclass


// ram_monitor
class ram_monitor extends uvm_monitor;
    `uvm_component_utils(ram_monitor)
    uvm_analysis_port #(ram_seq_item) send;
    virtual ram_if  r_if;
    ram_seq_item    r_item;

    function new(string name = "ram_mon", uvm_component c = null);
        super.new(name, c);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual ram_if)::get(this, "", "r_if", r_if))
            `uvm_fatal("ram_mon",
                       "build_phase : can't access virtual interface");

        send = new("WRITE", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);

        forever begin
            r_item = ram_seq_item::type_id::create("ram_seq_item");

            @(posedge r_if.clk);
            #1;
            r_item.we    = r_if.we;
            r_item.addr  = r_if.addr;
            r_item.wdata = r_if.wdata;
            r_item.rdata = r_if.rdata;


            send.write(r_item);
        end
    endtask
endclass

class ram_agent extends uvm_agent;
    `uvm_component_utils(ram_agent)

    ram_driver                    ram_drv;
    ram_monitor                   ram_mon;
    uvm_sequencer #(ram_seq_item) ram_sqr;

    function new(string name = "ram_agent", uvm_component c = null);
        super.new(name, c);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ram_drv = ram_driver::type_id::create("drv", this);
        ram_mon = ram_monitor::type_id::create("mon", this);
        ram_sqr = uvm_sequencer#(ram_seq_item)::type_id::create("sqr", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        ram_drv.seq_item_port.connect(ram_sqr.seq_item_export);
    endfunction

endclass


// ram_scoreboard
class ram_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(ram_scoreboard)
    uvm_analysis_imp #(ram_seq_item, ram_scoreboard) recv;
    int pass_cnt = 0, fail_cnt = 0;
    logic [7:0] ram_buffer[0:255];


    function new(string name = "ram_scb", uvm_component p = null);
        super.new(name, p);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        recv = new("READ", this);
    endfunction

    virtual function void write(ram_seq_item r_item);
        if (r_item.we) begin
            ram_buffer[r_item.addr] = r_item.wdata;
            if (r_item.wdata == r_item.rdata) begin
                `uvm_info("SCB", $sformatf(
                          "Pass !! we = %d, addr = %d, r_data =%d, w_data = %d",
                          r_item.we,
                          r_item.addr,
                          r_item.rdata,
                          r_item.wdata
                          ), UVM_HIGH);
                pass_cnt++;
            end else begin
                `uvm_error("SCB", "Fail !!");
                `uvm_info("SCB", r_item.c2string("SCB"), UVM_NONE);
                fail_cnt++;
            end
        end else begin
            if (r_item.rdata === ram_buffer[r_item.addr]) begin
                `uvm_info("SCB", $sformatf(
                          "Pass !! we = %d, addr = %d, r_data = %d, ram_buffer = %d",
                          r_item.we,
                          r_item.addr,
                          r_item.rdata,
                          ram_buffer[r_item.addr]
                          ), UVM_HIGH);
                pass_cnt++;
            end else begin
                `uvm_error("SCB", "\nFail !!");
                `uvm_info("SCB", r_item.c2string("SCB"), UVM_NONE);
                `uvm_info("SCB", $sformatf(
                          "ram_buffer = %d", ram_buffer[r_item.addr]),
                          UVM_HIGH);

                fail_cnt++;
            end
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);

        `uvm_info("SCB", $sformatf("\n**********************"), UVM_NONE);
        `uvm_info("SCB", $sformatf("** pass count = %2d **", pass_cnt),
                  UVM_NONE);
        `uvm_info("SCB", $sformatf("** fail count = %2d **", fail_cnt),
                  UVM_NONE);
        `uvm_info("SCB", $sformatf("\n**********************"), UVM_NONE);
    endfunction
endclass


class ram_environment extends uvm_env;
    `uvm_component_utils(ram_environment)
    ram_agent      ram_agt;
    ram_scoreboard ram_scb;


    function new(string name = "ram_env", uvm_component p = null);
        super.new(name, p);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ram_agt = ram_agent::type_id::create("agt", this);
        ram_scb = ram_scoreboard::type_id::create("scb", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        ram_agt.ram_mon.send.connect(ram_scb.recv);
    endfunction

endclass

class ram_test extends uvm_test;
    `uvm_component_utils(ram_test)

    ram_sequence    ram_seq;
    ram_environment ram_env;


    function new(string name = "ram_test", uvm_component c = null);
        super.new(name, c);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        ram_seq = ram_sequence::type_id::create("seq", this);
        ram_env = ram_environment::type_id::create("env", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);

        phase.raise_objection(this);
        ram_seq.start(ram_env.ram_agt.ram_sqr);
        phase.drop_objection(this);
    endtask



endclass


// tb_ram_uvm
module tb_ram_uvm ();

    logic clk = 0;

    always #5 clk = ~clk;

    ram_if r_if (clk);

    ram dut (
        .clk(clk),
        .we(r_if.we),
        .addr(r_if.addr),
        .wdata(r_if.wdata),
        .rdata(r_if.rdata)
    );

    initial begin
        $fsdbDumpfile("wave.fsdb");
        $fsdbDumpvars(0, tb_ram_uvm);
    end

    initial begin


        uvm_config_db#(virtual ram_if)::set(null, "*", "r_if", r_if);

        // run uvm for ram_test;
        run_test("ram_test");

    end

endmodule
