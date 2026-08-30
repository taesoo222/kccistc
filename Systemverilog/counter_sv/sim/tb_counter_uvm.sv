`timescale 1ns / 1ps
`include "uvm_macros.svh"
import uvm_pkg::*;

interface counter_if(input clk);
  logic       rst_n;
  logic       enable;
  logic [2:0] counter;
  logic       o_tick;


  clocking drv_cb @(posedge clk);
    default input #1step output #1;
    output rst_n;
    output enable;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
    input         rst_n;
    input         enable;
    input         counter;
    input         o_tick;
  endclocking

  modport drv_mb (clocking drv_cb, input clk);
  modport mon_mb (clocking mon_cb, input clk);


  // 1. property: to be become counter_value 0 occurated after reset 0 when posedge clk
  // |=>: if the antecedent is true, check the consequent on the next clock
  property p_reset_clear_counter;
    @(posedge clk)(!rst_n)|=>(counter == 3'b000);
  endproperty

  // assertion
  A_RESET_CLEAR:assert property (p_reset_clear_counter)
      else `uvm_error("[ASSERT]","RESET_ASSERT property p_reset_clear_counter!!")

endinterface

class counter_seq_item extends uvm_sequence_item;
  rand bit       enable;
       bit       rst_n;
       bit [2:0] counter;
       bit       o_tick;

  constraint c_en {enable dist {0 := 1, 1 := 9};}

  function new(string name = "counter_seq_item");
    super.new(name);
  endfunction

  `uvm_object_utils_begin(counter_seq_item)
    `uvm_field_int(enable,UVM_DEFAULT)
    `uvm_field_int(rst_n,UVM_DEFAULT)
    `uvm_field_int(counter,UVM_DEFAULT)
    `uvm_field_int(o_tick,UVM_DEFAULT)
  `uvm_object_utils_end

  virtual function string convert2string();
    return $sformatf("reset_n = %b, enable = %b, counter = %d, o_tick = %b", rst_n, enable, counter, o_tick);
  endfunction

endclass

// sequence
class counter_sequence extends uvm_sequence #(counter_seq_item);
  `uvm_object_utils(counter_sequence)

  function new (string name = "counter_seq");
    super.new(name);
  endfunction

  virtual task body();
      counter_seq_item c_item;
  // reset test: rst_n = 0, enable = 1
 // repeat(3) begin
   // c_item = counter_seq_item::type_id::create("c_item");
   // start_item(c_item);
   // c_item.rst_n = 0;
   // c_item.enable = 0;
   // finish_item(c_item);
  //end

  // random case rst_n=1, enable = random
  repeat (100) begin
      // new counter_seq_item
      c_item = counter_seq_item::type_id::create("c_item");
      // randomized()
      start_item(c_item);
      if(!c_item.randomize())begin
        `uvm_fatal(get_type_name(),"c_item randomized fail")
      end
      c_item.rst_n = 1;
      finish_item(c_item);

    end
  endtask

endclass

// reset_sequence
class counter_reset_sequence extends uvm_sequence #(counter_seq_item);
  `uvm_object_utils(counter_reset_sequence)

  function new (string name = "counter_reset_seq");
    super.new(name);
  endfunction

  virtual task body();
      counter_seq_item c_item;
  // reset test: rst_n = 0, enable = 1
  repeat(5) begin
    c_item = counter_seq_item::type_id::create("c_item");
    start_item(c_item);
    c_item.rst_n = 0;
    c_item.enable = 0;
    finish_item(c_item);
  end

  endtask

endclass

// driver
class counter_driver extends uvm_driver #(counter_seq_item);
     `uvm_component_utils(counter_driver)
     virtual counter_if c_if;
     counter_seq_item c_item;

     function new(string name = "counter_drv",uvm_component c = null);
       super.new(name, c);
     endfunction

     // build phase
     virtual function void build_phase(uvm_phase phase);
       super.build_phase(phase);
       // interface
       if(!uvm_config_db#(virtual counter_if)::get(this,"","c_if",c_if)) begin
         `uvm_fatal(get_name(),"unable to access counter interface")
       end
     endfunction

     virtual task pre_set();
         c_if.drv_cb.rst_n   <= 1'b0;
         c_if.drv_cb.enable  <= 1'b0;
         @(c_if.drv_cb);
     endtask

     // run phase
     virtual task run_phase (uvm_phase phase);
       super.run_phase(phase);
      // pre_set();
       forever begin
       // drive
       // get_seq_item
       seq_item_port.get_next_item(c_item);
        @(c_if.drv_cb);
        c_if.drv_cb.rst_n   <= c_item.rst_n;
        c_if.drv_cb.enable  <= c_item.enable;
      seq_item_port.item_done();
      end
  endtask

endclass

// monitor
class counter_monitor extends uvm_monitor;
  `uvm_component_utils(counter_monitor)

  virtual counter_if c_if;
  counter_seq_item  c_item;
  uvm_analysis_port#(counter_seq_item) send;

  function new(string name = "counter_mon",uvm_component c = null);
    super.new(name, c);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
      // interface
      if(!uvm_config_db#(virtual counter_if)::get(this,"","c_if",c_if)) begin
        `uvm_fatal(get_name(),"unable to access counter interface")
      end
      send = new("write",this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    forever begin
      // count_seq_item new
      c_item = counter_seq_item::type_id::create("counter_seq_item",this);
      @(c_if.mon_cb);
      c_item.rst_n    = c_if.mon_cb.rst_n;
      c_item.enable   = c_if.mon_cb.enable;
      c_item.counter  = c_if.mon_cb.counter;
      c_item.o_tick   = c_if.mon_cb.o_tick;

      send.write(c_item);
    end
  endtask
endclass

// agent
class counter_agent extends uvm_agent;
  `uvm_component_utils(counter_agent)
  counter_driver                        drv;
  counter_monitor                       mon;
  uvm_sequencer #(counter_seq_item) sqr;

  function new (string name = "counter_agt",uvm_component c = null);
     super.new(name, c);
  endfunction

  virtual function void build_phase(uvm_phase phase);
   super.build_phase(phase);
    drv = counter_driver::type_id::create("drv",this);
    mon = counter_monitor::type_id::create("mon",this);
    sqr = uvm_sequencer#(counter_seq_item)::type_id::create("sqr",this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction

endclass

// scoreboard
class counter_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(counter_scoreboard)
  uvm_analysis_imp#(counter_seq_item,counter_scoreboard) recv;

  bit [2:0] expected_count = 0;
  int pass_cnt = 0;
  int fail_cnt = 0;
  int skip_cnt = 0;

  function new(string name = "counter_scb", uvm_component c = null);
    super.new(name, c);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    recv =  new("READ",this);
  endfunction

  virtual function void write(counter_seq_item c_item);
      `uvm_info(get_type_name(),c_item.convert2string(), UVM_HIGH)

      if(!c_item.rst_n)begin
        `uvm_info(get_type_name(),$sformatf("To skip: counter is x "),UVM_NONE) 
        skip_cnt++;
        expected_count = 0;
      end else begin
        // pass/fail
        if(expected_count == c_item.counter) begin
          `uvm_info(get_type_name(),$sformatf("PASS !! expect:%d,counter:%d",expected_count, c_item.counter), UVM_HIGH) 

          pass_cnt++;
        end else  begin
          `uvm_error(get_type_name(),$sformatf("FAIL !! expect:%d,counter:%d",expected_count, c_item.counter)) 

          fail_cnt++;
      end
      if(c_item.rst_n&&c_item.enable)
      expected_count++;
    end
  endfunction

  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SCB",$sformatf("\n            "),UVM_NONE)
    `uvm_info("SCB",$sformatf("Result Pass:%d",pass_cnt),UVM_NONE)
    `uvm_info("SCB",$sformatf("Result Fail:%d",fail_cnt),UVM_NONE)
    `uvm_info("SCB",$sformatf("Result Skip:%d",skip_cnt),UVM_NONE)
  endfunction

endclass

// environment
class counter_environment extends uvm_env;
  `uvm_component_utils(counter_environment)
  // instance object
  counter_agent       agt;
  counter_scoreboard  scb;

  function new(string name = "counter_env",uvm_component c = null);
    super.new(name, c);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agt = counter_agent::type_id::create("agt",this);
    scb = counter_scoreboard::type_id::create("scb",this);
  endfunction


  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agt.mon.send.connect(scb.recv);
  endfunction

endclass


// test
class counter_test extends uvm_test;
  `uvm_component_utils(counter_test)
  counter_sequence    seq;
  counter_reset_sequence    seq_reset;
  counter_environment env;


  function new(string name = "counter_test", uvm_component c = null);
    super.new(name, c);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    seq = counter_sequence::type_id::create("seq",this);
    seq_reset = counter_reset_sequence::type_id::create("seq_reset",this);
    env = counter_environment::type_id::create("env",this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);

    phase.raise_objection(this);
      seq_reset.start(env.agt.sqr);
    phase.drop_objection(this);

    phase.raise_objection(this);
      seq.start(env.agt.sqr);
      repeat(2)@(posedge  env.agt.drv.c_if.clk);
    phase.drop_objection(this);
  endtask

endclass

module tb_counter();

  logic clk = 0;
  always #5 clk = ~clk;


  counter_if c_if(clk);
  counter dut(
    .clk(clk),
    .rst_n(c_if.rst_n),
    .enable(c_if.enable),
    .counter(c_if.counter),
    .o_tick(c_if.o_tick)
  );

  initial begin
    //vcs wave db
    $fsdbDumpfile("wave.fsdb");
    $fsdbDumpvars(0,tb_counter);
  end

  initial begin
    // interface test
    uvm_config_db#(virtual counter_if)::set(null,"*","c_if",c_if);
    // run test
    run_test("counter_test");
  end

  endmodule
