`timescale 1ns / 1ps

`include "uvm_macros.svh"
import uvm_pkg::*;

// ---------------------------------------------------------------
// interface : apb_requester 의 모든 포트를 벡터로 묶어서 노출
// ---------------------------------------------------------------
interface apb_req_if (
    input clk
);
    logic        rst_n;

    // with CPU
    logic [31:0] bus_addr;
    logic [31:0] bus_wdata;
    logic        transfer;
    logic        bus_we;
    logic        ready;
    logic [31:0] bus_rdata;

    // apb interface (0:BRAM, 1:GPI, 2:GPO, 3:GPIO, 4:FND, 5:UART, 6:-)
    logic [ 6:0] PSEL;
    logic        PENABLE;
    logic        PWRITE;
    logic [31:0] PADDR;
    logic [31:0] PWDATA;
    logic [ 6:0] PREADY;
    logic [31:0] PRDATA[7];

endinterface


// ---------------------------------------------------------------
// seq_item
// ---------------------------------------------------------------
class apb_req_seq_item extends uvm_sequence_item;

    // stimulus (CPU 쪽에서 준다)
    rand logic [31:0] bus_addr;
    rand logic [31:0] bus_wdata;
    rand logic        bus_we;

    // monitor 가 채워주는 결과
    logic      [31:0] paddr;
    logic      [31:0] pwdata;
    logic              pwrite;
    logic      [ 6:0] psel;
    logic      [31:0] bus_rdata;

    // BRAM(0x1000_0000~0x1000_FFFF) 위주로 뽑되, 가끔 주변장치/미정의 영역도 섞는다
    constraint c_addr_ {
        bus_addr[1:0] == 2'b00;  // word aligned
        bus_addr dist {
            [32'h1000_0000 : 32'h1000_01FF] :/ 70,  // BRAM
            32'h2000_0000                   :/ 10,  // GPI
            32'h2000_0100                   :/ 10,  // GPO
            32'h3000_0000                   :/ 10   // 미정의 영역 (decode 안 됨)
        };
    }

    constraint c_we_ {
        bus_we dist {
            0 := 1,
            1 := 1
        };
    }

    `uvm_object_utils_begin(apb_req_seq_item)
        `uvm_field_int(bus_addr, UVM_DEFAULT)
        `uvm_field_int(bus_wdata, UVM_DEFAULT)
        `uvm_field_int(bus_we, UVM_DEFAULT)
        `uvm_field_int(paddr, UVM_DEFAULT)
        `uvm_field_int(pwdata, UVM_DEFAULT)
        `uvm_field_int(pwrite, UVM_DEFAULT)
        `uvm_field_int(psel, UVM_DEFAULT)
        `uvm_field_int(bus_rdata, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "apb_req_seq_item");
        super.new(name);
    endfunction

    function string c2string(string name);
        return $sformatf(
            "[%s] addr=%08h wdata=%08h we=%0d | paddr=%08h pwdata=%08h psel=%07b rdata=%08h",
            name, bus_addr, bus_wdata, bus_we, paddr, pwdata, psel, bus_rdata);
    endfunction
endclass


// ---------------------------------------------------------------
// sequence
// ---------------------------------------------------------------
class apb_req_sequence extends uvm_sequence #(apb_req_seq_item);
    `uvm_object_utils(apb_req_sequence)

    function new(string name = "apb_req_seq");
        super.new(name);
    endfunction

    virtual task body();
        apb_req_seq_item item;

        repeat (200) begin
            item = apb_req_seq_item::type_id::create("apb_req_seq_item");
            start_item(item);
            if (!item.randomize()) `uvm_fatal("apb_req_seq", "randomize fail");
            finish_item(item);
        end
    endtask
endclass


// ---------------------------------------------------------------
// driver : CPU 역할 (transfer 를 걸고 ready 를 기다림 -> 한 번에 1트랜잭션)
// ---------------------------------------------------------------
class apb_req_driver extends uvm_driver #(apb_req_seq_item);
    `uvm_component_utils(apb_req_driver)

    virtual apb_req_if vif;

    function new(string name = "apb_req_drv", uvm_component c = null);
        super.new(name, c);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual apb_req_if)::get(this, "", "vif", vif))
            `uvm_fatal("apb_req_drv", "can't get vif");
    endfunction

    virtual task run_phase(uvm_phase phase);
        apb_req_seq_item item;

        vif.transfer  <= 0;
        vif.bus_we    <= 0;
        vif.bus_addr  <= 0;
        vif.bus_wdata <= 0;

        super.run_phase(phase);
        forever begin
            seq_item_port.get_next_item(item);

            @(negedge vif.clk);
            vif.bus_addr  <= item.bus_addr;
            vif.bus_wdata <= item.bus_wdata;
            vif.bus_we    <= item.bus_we;
            vif.transfer  <= 1'b1;

            @(negedge vif.clk);
            vif.transfer <= 1'b0;

            // ready 뜰 때까지 대기 (미정의 주소는 별도 directed test 에서 timeout 으로 다룸)
            wait (vif.ready === 1'b1);
            @(negedge vif.clk);

            seq_item_port.item_done();
        end
    endtask
endclass


// ---------------------------------------------------------------
// slave responder : apb_requester 입장에서 "가짜 Completer" 역할
//   - index0 (BRAM) 은 실제 메모리처럼 write 한 값을 read 로 돌려줌
//   - index1~6 (주변장치) 은 write 는 무시, read 는 고정 패턴을 돌려줌
// ---------------------------------------------------------------
class apb_slave_responder extends uvm_component;
    `uvm_component_utils(apb_slave_responder)

    virtual apb_req_if vif;
    logic [31:0] bram_mem[bit[27:0]];  // 주소(하위 28비트) -> data

    function new(string name = "apb_slave", uvm_component c = null);
        super.new(name, c);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual apb_req_if)::get(this, "", "vif", vif))
            `uvm_fatal("apb_slave", "can't get vif");
    endfunction

    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);

        vif.PREADY   <= 7'b0;
        for (int i = 0; i < 7; i++) vif.PRDATA[i] <= 32'hDEAD_0000 + i;

        forever begin
            @(posedge vif.clk);
            if (|vif.PSEL && vif.PENABLE) begin
                int sel;
                sel = 0;
                for (int i = 0; i < 7; i++) if (vif.PSEL[i]) sel = i;

                if (sel == 0) begin
                    // BRAM
                    if (vif.PWRITE) bram_mem[vif.PADDR[27:0]] = vif.PWDATA;
                    vif.PRDATA[0] <= bram_mem.exists(
                        vif.PADDR[27:0]
                    ) ? bram_mem[vif.PADDR[27:0]] : 32'h0;
                end else begin
                    // 주변장치 : write 는 무시, read 는 고정 패턴
                    vif.PRDATA[sel] <= 32'hCAFE_0000 + sel;
                end

                vif.PREADY[sel] <= 1'b1;
                @(posedge vif.clk);
                vif.PREADY[sel] <= 1'b0;
            end
        end
    endtask
endclass


// ---------------------------------------------------------------
// monitor
// ---------------------------------------------------------------
class apb_req_monitor extends uvm_monitor;
    `uvm_component_utils(apb_req_monitor)
    uvm_analysis_port #(apb_req_seq_item) send;

    virtual apb_req_if vif;

    function new(string name = "apb_req_mon", uvm_component c = null);
        super.new(name, c);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual apb_req_if)::get(this, "", "vif", vif))
            `uvm_fatal("apb_req_mon", "can't get vif");
        send = new("send", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        apb_req_seq_item item;
        super.run_phase(phase);

        forever begin
            @(posedge vif.clk);
            if (vif.ready) begin
                item          = apb_req_seq_item::type_id::create("apb_req_seq_item");
                item.bus_addr  = vif.bus_addr;
                item.bus_wdata = vif.bus_wdata;
                item.bus_we    = vif.bus_we;
                item.paddr     = vif.PADDR;
                item.pwdata    = vif.PWDATA;
                item.pwrite    = vif.PWRITE;
                item.psel      = vif.PSEL;
                item.bus_rdata = vif.bus_rdata;
                send.write(item);
            end
        end
    endtask
endclass


class apb_req_agent extends uvm_agent;
    `uvm_component_utils(apb_req_agent)

    apb_req_driver                    drv;
    apb_req_monitor                   mon;
    apb_slave_responder               slv;
    uvm_sequencer #(apb_req_seq_item) sqr;

    function new(string name = "apb_req_agent", uvm_component c = null);
        super.new(name, c);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        drv = apb_req_driver::type_id::create("drv", this);
        mon = apb_req_monitor::type_id::create("mon", this);
        slv = apb_slave_responder::type_id::create("slv", this);
        sqr = uvm_sequencer#(apb_req_seq_item)::type_id::create("sqr", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
endclass


// ---------------------------------------------------------------
// scoreboard : APB 기본동작 검증 3항목 + BRAM write/read 를 그대로 코드로 옮김
// ---------------------------------------------------------------
class apb_req_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(apb_req_scoreboard)
    uvm_analysis_imp #(apb_req_seq_item, apb_req_scoreboard) recv;

    int pass_cnt = 0, fail_cnt = 0;

    // BRAM(PSEL0) 전용 shadow memory : write 한 값을 기억해뒀다가 read 와 대조 (RAW 체크)
    logic [31:0] bram_shadow[bit[27:0]];

    function new(string name = "apb_req_scb", uvm_component p = null);
        super.new(name, p);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        recv = new("recv", this);
    endfunction

    // 주소 -> 기대 PSEL 계산 (address_decoder.sv 로직 그대로)
    function logic [6:0] expected_psel(logic [31:0] addr);
        logic [6:0] sel;
        sel = 7'b0;
        case (addr[31:28])
            4'b0001: sel[0] = 1'b1;
            4'b0010: begin
                case (addr[11:8])
                    4'b0000: sel[1] = 1'b1;
                    4'b0001: sel[2] = 1'b1;
                    4'b0010: sel[3] = 1'b1;
                    4'b0011: sel[4] = 1'b1;
                    4'b0100: sel[5] = 1'b1;
                    4'b0101: sel[6] = 1'b1;
                    default: sel = 7'b0;
                endcase
            end
            default: sel = 7'b0;
        endcase
        return sel;
    endfunction

    virtual function void write(apb_req_seq_item item);
        logic [6:0] exp_sel;
        logic [31:0] exp_paddr;
        bit ok;

        ok = 1'b1;
        exp_sel   = expected_psel(item.bus_addr);
        exp_paddr = {4'b0000, item.bus_addr[27:0]};

        // 검증 1: 주소 디코딩(select)
        if (item.psel !== exp_sel) begin
            `uvm_error("SCB", $sformatf(
                       "PSEL mismatch! addr=%08h exp=%07b got=%07b",
                       item.bus_addr, exp_sel, item.psel));
            ok = 1'b0;
        end

        // 검증 2: 주소/데이터 무결성 (PADDR)
        if (item.paddr !== exp_paddr) begin
            `uvm_error("SCB", $sformatf(
                       "PADDR mismatch! exp=%08h got=%08h", exp_paddr,
                       item.paddr));
            ok = 1'b0;
        end

        // 검증 3: write 시 PWDATA 무결성
        if (item.bus_we && item.pwdata !== item.bus_wdata) begin
            `uvm_error("SCB", $sformatf(
                       "PWDATA mismatch! exp=%08h got=%08h", item.bus_wdata,
                       item.pwdata));
            ok = 1'b0;
        end

        // 검증 4: BRAM RAW (write 한 값이 read 로 정확히 돌아오는지)
        if (exp_sel[0]) begin  // BRAM 접근일 때만
            if (item.bus_we) begin
                bram_shadow[item.bus_addr[27:0]] = item.bus_wdata;
            end else begin
                logic [31:0] exp_rdata;
                exp_rdata = bram_shadow.exists(
                    item.bus_addr[27:0]
                ) ? bram_shadow[item.bus_addr[27:0]] : 32'h0;

                if (item.bus_rdata !== exp_rdata) begin
                    `uvm_error("SCB", $sformatf(
                               "BRAM RAW mismatch! addr=%08h exp=%08h got=%08h",
                               item.bus_addr, exp_rdata, item.bus_rdata));
                    ok = 1'b0;
                end
            end
        end

        if (ok) pass_cnt++;
        else begin
            fail_cnt++;
            `uvm_info("SCB", item.c2string("FAIL"), UVM_NONE);
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SCB", $sformatf("\n**********************"), UVM_NONE);
        `uvm_info("SCB", $sformatf("** pass count = %3d **", pass_cnt), UVM_NONE);
        `uvm_info("SCB", $sformatf("** fail count = %3d **", fail_cnt), UVM_NONE);
        `uvm_info("SCB", $sformatf("**********************"), UVM_NONE);
    endfunction
endclass


// ---------------------------------------------------------------
// coverage
// ---------------------------------------------------------------
class apb_req_coverage extends uvm_subscriber #(apb_req_seq_item);
    `uvm_component_utils(apb_req_coverage)

    apb_req_seq_item item;

    covergroup apb_req_cg;
        option.per_instance = 1;
        cp_we: coverpoint item.bus_we;
        cp_sel: coverpoint item.psel {
            bins bram       = {7'b0000001};
            bins periph[]   = {7'b0000010, 7'b0000100, 7'b0001000,
                                7'b0010000, 7'b0100000, 7'b1000000};
            bins undecoded  = {7'b0000000};
        }
        cx_we_sel: cross cp_we, cp_sel;

        // BRAM 영역 내부 주소가 골고루 찍혔는지
        cp_addr: coverpoint item.bus_addr {
            bins bram_low   = {[32'h1000_0000 : 32'h1000_007F]};
            bins bram_mid   = {[32'h1000_0080 : 32'h1000_00FF]};
            bins bram_high  = {[32'h1000_0100 : 32'h1000_01FF]};
            bins gpi        = {32'h2000_0000};
            bins gpo        = {32'h2000_0100};
            bins undecoded  = {32'h3000_0000};
        }

        // write 데이터의 corner case가 나왔는지
        cp_wdata: coverpoint item.bus_wdata {
            bins zero    = {32'h0000_0000};
            bins all_one = {32'hFFFF_FFFF};
            bins others  = default;
        }

        cx_wdata_addr: cross cp_wdata, cp_addr;
    endgroup

    function new(string name = "apb_req_cov", uvm_component c = null);
        super.new(name, c);
        apb_req_cg = new();
    endfunction

    virtual function void write(apb_req_seq_item t);
        item = t;
        apb_req_cg.sample();
    endfunction

    virtual function void report_phase(uvm_phase phase);
        `uvm_info("COV", $sformatf("Overall  = %.1f %%",
                                    apb_req_cg.get_coverage()), UVM_NONE);
        `uvm_info("COV", $sformatf("we       = %.1f %%",
                                    apb_req_cg.cp_we.get_coverage()), UVM_NONE);
        `uvm_info("COV", $sformatf("sel      = %.1f %%",
                                    apb_req_cg.cp_sel.get_coverage()), UVM_NONE);
        `uvm_info("COV", $sformatf("addr     = %.1f %%",
                                    apb_req_cg.cp_addr.get_coverage()), UVM_NONE);
        `uvm_info("COV", $sformatf("wdata    = %.1f %%",
                                    apb_req_cg.cp_wdata.get_coverage()), UVM_NONE);
    endfunction
endclass


class apb_req_environment extends uvm_env;
    `uvm_component_utils(apb_req_environment)

    apb_req_agent       agt;
    apb_req_scoreboard   scb;
    apb_req_coverage     cov;

    function new(string name = "apb_req_env", uvm_component p = null);
        super.new(name, p);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agt = apb_req_agent::type_id::create("agt", this);
        scb = apb_req_scoreboard::type_id::create("scb", this);
        cov = apb_req_coverage::type_id::create("cov", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agt.mon.send.connect(scb.recv);
        agt.mon.send.connect(cov.analysis_export);
    endfunction
endclass


class apb_req_test extends uvm_test;
    `uvm_component_utils(apb_req_test)

    apb_req_sequence    seq;
    apb_req_environment env;

    function new(string name = "apb_req_test", uvm_component c = null);
        super.new(name, c);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        seq = apb_req_sequence::type_id::create("seq", this);
        env = apb_req_environment::type_id::create("env", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        phase.raise_objection(this);
        seq.start(env.agt.sqr);
        phase.drop_objection(this);
    endtask
endclass


// ---------------------------------------------------------------
// top
// ---------------------------------------------------------------
module tb_apb_requester_uvm ();

    logic clk = 0;
    always #5 clk = ~clk;

    apb_req_if a_if (clk);

    initial begin
        a_if.rst_n = 0;
        #12 a_if.rst_n = 1;
    end

    apb_requester dut (
        .clk      (clk),
        .rst_n    (a_if.rst_n),
        .bus_addr (a_if.bus_addr),
        .bus_wdata(a_if.bus_wdata),
        .transfer (a_if.transfer),
        .bus_we   (a_if.bus_we),
        .ready    (a_if.ready),
        .bus_rdata(a_if.bus_rdata),
        .PREADY0  (a_if.PREADY[0]),
        .PREADY1  (a_if.PREADY[1]),
        .PREADY2  (a_if.PREADY[2]),
        .PREADY3  (a_if.PREADY[3]),
        .PREADY4  (a_if.PREADY[4]),
        .PREADY5  (a_if.PREADY[5]),
        .PREADY6  (a_if.PREADY[6]),
        .PRDATA0  (a_if.PRDATA[0]),
        .PRDATA1  (a_if.PRDATA[1]),
        .PRDATA2  (a_if.PRDATA[2]),
        .PRDATA3  (a_if.PRDATA[3]),
        .PRDATA4  (a_if.PRDATA[4]),
        .PRDATA5  (a_if.PRDATA[5]),
        .PRDATA6  (a_if.PRDATA[6]),
        .PADDR    (a_if.PADDR),
        .PWDATA   (a_if.PWDATA),
        .PWRITE   (a_if.PWRITE),
        .PENABLE  (a_if.PENABLE),
        .PSEL0    (a_if.PSEL[0]),
        .PSEL1    (a_if.PSEL[1]),
        .PSEL2    (a_if.PSEL[2]),
        .PSEL3    (a_if.PSEL[3]),
        .PSEL4    (a_if.PSEL[4]),
        .PSEL5    (a_if.PSEL[5]),
        .PSEL6    (a_if.PSEL[6])
    );

    initial begin
        $fsdbDumpfile("wave.fsdb");
        $fsdbDumpvars(0, tb_apb_requester_uvm);
    end

    initial begin
        uvm_config_db#(virtual apb_req_if)::set(null, "*", "vif", a_if);
        run_test("apb_req_test");
    end

endmodule
