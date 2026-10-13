`timescale 1ns / 1ps
`include "uvm_macros.svh"
import uvm_pkg::*;

interface cpu_if (
    input logic clk
);
    logic        rst_n;
    logic [31:0] instr_code = 32'h00000013; // x0 = x0 + 0
    logic [31:0] instr_addr;
    logic [ 3:0] alu_control;
    logic [31:0] daddr;
    logic [31:0] dwdata;
    logic        dwe;
    logic        rf_we;
    logic        alusrc_sel;
    logic [ 2:0] itype;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst_n, instr_code, instr_addr, alu_control;
        input daddr, dwdata, dwe, rf_we, alusrc_sel, itype;
    endclocking
endinterface

typedef enum int {
    ADD,
    SUB,
    SLL,
    SLT,
    SLTU,
    XOR,
    SRL,
    SRA,
    OR,
    AND,
    ADDI,
    SLTI,
    SLTIU,
    XORI,
    ORI,
    ANDI,
    SLLI,
    SRLI,
    SRAI,
    ERROR
} cpu_command_e;

typedef enum int {
    FETCH,
    DECODE,
    EXECUTE
} cpu_phase_e;


class cpu_seq_item extends uvm_sequence_item;
    cpu_command_e command;
    rand logic [4:0] rs1, rs2, rd;
    rand logic signed [11:0] imm;
    logic [31:0] instr_code;
    constraint c_command {
        if (command inside {SLLI, SRLI, SRAI})
        imm inside {[0 : 31]};
    }


    cpu_phase_e sample_phase;
    logic rst_n;
    logic [31:0] instr_addr_before, instr_addr, daddr, dwdata;
    logic [3:0] alu_control;
    logic dwe, rf_we, alusrc_sel;
    logic [2:0] itype;

    `uvm_object_utils_begin(cpu_seq_item)
        `uvm_field_int(rst_n, UVM_DEFAULT)
        `uvm_field_enum(cpu_command_e, command, UVM_DEFAULT)
        `uvm_field_int(rs1, UVM_DEFAULT)
        `uvm_field_int(rs2, UVM_DEFAULT)
        `uvm_field_int(rd, UVM_DEFAULT)
        `uvm_field_int(imm, UVM_DEFAULT)
        `uvm_field_int(instr_code, UVM_DEFAULT | UVM_HEX)
        `uvm_field_int(daddr, UVM_DEFAULT | UVM_HEX)
        `uvm_field_int(dwdata, UVM_DEFAULT | UVM_HEX)
    `uvm_object_utils_end

    function new(string name = "cpu_seq_item");
        super.new(name);
    endfunction
    virtual function string convert2string();
        return $sformatf(
            "%s %s pc=%08h instr=%08h alu=%h rf_we=%b alusrc=%b daddr=%08h dwdata=%08h",
            sample_phase.name(),
            command.name(),
            instr_addr_before,
            instr_code,
            alu_control,
            rf_we,
            alusrc_sel,
            daddr,
            dwdata
        );
    endfunction
endclass

class cpu_init_sequence extends uvm_sequence #(cpu_seq_item);
    `uvm_object_utils(cpu_init_sequence)

    cpu_seq_item c_item;
    virtual cpu_if c_if;

    function new(string name = "cpu_init_sequence");
        super.new(name);
    endfunction

    virtual task body();
        if (!uvm_config_db#(virtual cpu_if)::get(
            null, "", "c_if", c_if
        ))
            `uvm_fatal("SEQ",
                "init_sequence : can't access virtual interface")

        c_if.rst_n = 1'b0;
        repeat (2) @(posedge c_if.clk);

        #1;
        c_if.rst_n <= 1'b1;

        for (int i = 1; i < 32; i++) begin
            c_item = cpu_seq_item::type_id::create("init_c_item");

            start_item(c_item);

            c_item.command = ADDI;
            c_item.rs1 = 0;
            c_item.rs2 = 0;
            c_item.rd = 5'(i);
            c_item.imm = 12'(i);

            c_item.instr_code = {
                c_item.imm, c_item.rs1, 3'b000,
                c_item.rd, 7'b0010011
            };

            finish_item(c_item);
        end

    endtask
endclass

class cpu_add_sequence extends uvm_sequence #(cpu_seq_item);
    `uvm_object_utils(cpu_add_sequence)
    cpu_seq_item c_item;
    int repeat_count = 15000;

    function new(string name = "cpu_add_sequence");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info("SEQ", $sformatf("START ADD, random count=%0d", repeat_count), UVM_LOW)
        repeat (repeat_count) begin
            c_item = cpu_seq_item::type_id::create("c_item");
            start_item(c_item);
            c_item.command = ADD;
            if (!c_item.randomize())
                `uvm_fatal("SEQ", "ADD randomization failed")

            c_item.instr_code = {7'b0000000, c_item.rs2, c_item.rs1,
                                 3'b000, c_item.rd, 7'b0110011};
            finish_item(c_item);
        end
    endtask
endclass


class cpu_sub_sequence extends uvm_sequence #(cpu_seq_item);
    `uvm_object_utils(cpu_sub_sequence)
    cpu_seq_item c_item;
    int repeat_count = 15000;

    function new(string name = "cpu_sub_sequence");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info("SEQ", $sformatf("START SUB, random count=%0d", repeat_count), UVM_LOW)
        repeat (repeat_count) begin
            c_item = cpu_seq_item::type_id::create("c_item");
            start_item(c_item);
            c_item.command = SUB;
            if (!c_item.randomize())
                `uvm_fatal("SEQ", "SUB randomization failed")
            c_item.instr_code = {7'b0100000, c_item.rs2, c_item.rs1,
                                 3'b000, c_item.rd, 7'b0110011};
            finish_item(c_item);
        end
    endtask
endclass


class cpu_sll_sequence extends uvm_sequence #(cpu_seq_item);
    `uvm_object_utils(cpu_sll_sequence)
    cpu_seq_item c_item;
    int repeat_count = 15000;

    function new(string name = "cpu_sll_sequence");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info("SEQ", $sformatf("START SLL, random count=%0d", repeat_count), UVM_LOW)
        repeat (repeat_count) begin
            c_item = cpu_seq_item::type_id::create("c_item");
            start_item(c_item);
            c_item.command = SLL;
            if (!c_item.randomize())
                `uvm_fatal("SEQ", "SLL randomization failed")
            c_item.instr_code = {7'b0000000, c_item.rs2, c_item.rs1,
                                 3'b001, c_item.rd, 7'b0110011};
            finish_item(c_item);
        end
    endtask
endclass


class cpu_slt_sequence extends uvm_sequence #(cpu_seq_item);
    `uvm_object_utils(cpu_slt_sequence)
    cpu_seq_item c_item;
    int repeat_count = 15000;

    function new(string name = "cpu_slt_sequence");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info("SEQ", $sformatf("START SLT, random count=%0d", repeat_count), UVM_LOW)
        repeat (repeat_count) begin
            c_item = cpu_seq_item::type_id::create("c_item");
            start_item(c_item);
            c_item.command = SLT;
            if (!c_item.randomize())
                `uvm_fatal("SEQ", "SLT randomization failed")

            c_item.instr_code = {7'b0000000, c_item.rs2, c_item.rs1,
                                 3'b010, c_item.rd, 7'b0110011};
            finish_item(c_item);
        end
    endtask
endclass


class cpu_sltu_sequence extends uvm_sequence #(cpu_seq_item);
    `uvm_object_utils(cpu_sltu_sequence)
    cpu_seq_item c_item;
    int repeat_count = 15000;

    function new(string name = "cpu_sltu_sequence");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info("SEQ", $sformatf("START SLTU, random count=%0d", repeat_count), UVM_LOW)
        repeat (repeat_count) begin
            c_item = cpu_seq_item::type_id::create("c_item");
            start_item(c_item);
            c_item.command = SLTU;
            if (!c_item.randomize())
                `uvm_fatal("SEQ", "SLTU randomization failed")

            c_item.instr_code = {7'b0000000, c_item.rs2, c_item.rs1,
                                 3'b011, c_item.rd, 7'b0110011};
            finish_item(c_item);
        end
    endtask
endclass


class cpu_xor_sequence extends uvm_sequence #(cpu_seq_item);
    `uvm_object_utils(cpu_xor_sequence)
    cpu_seq_item c_item;
    int repeat_count = 15000;

    function new(string name = "cpu_xor_sequence");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info("SEQ", $sformatf("START XOR, random count=%0d", repeat_count), UVM_LOW)
        repeat (repeat_count) begin
            c_item = cpu_seq_item::type_id::create("c_item");
            start_item(c_item);
            c_item.command = XOR;
            if (!c_item.randomize())
                `uvm_fatal("SEQ", "XOR randomization failed")

            c_item.instr_code = {7'b0000000, c_item.rs2, c_item.rs1,
                                 3'b100, c_item.rd, 7'b0110011};
            finish_item(c_item);
        end
    endtask
endclass


class cpu_srl_sequence extends uvm_sequence #(cpu_seq_item);
    `uvm_object_utils(cpu_srl_sequence)
    cpu_seq_item c_item;
    int repeat_count = 15000;

    function new(string name = "cpu_srl_sequence");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info("SEQ", $sformatf("START SRL, random count=%0d", repeat_count), UVM_LOW)
        repeat (repeat_count) begin
            c_item = cpu_seq_item::type_id::create("c_item");
            start_item(c_item);
            c_item.command = SRL;
            if (!c_item.randomize())
                `uvm_fatal("SEQ", "SRL randomization failed")

            c_item.instr_code = {7'b0000000, c_item.rs2, c_item.rs1,
                                 3'b101, c_item.rd, 7'b0110011};
            finish_item(c_item);
        end
    endtask
endclass


class cpu_sra_sequence extends uvm_sequence #(cpu_seq_item);
    `uvm_object_utils(cpu_sra_sequence)
    cpu_seq_item c_item;
    int repeat_count = 15000;

    function new(string name = "cpu_sra_sequence");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info("SEQ", $sformatf("START SRA, random count=%0d", repeat_count), UVM_LOW)
        repeat (repeat_count) begin
            c_item = cpu_seq_item::type_id::create("c_item");
            start_item(c_item);
            c_item.command = SRA;
            if (!c_item.randomize())
                `uvm_fatal("SEQ", "SRA randomization failed")

            c_item.instr_code = {7'b0100000, c_item.rs2, c_item.rs1,
                                 3'b101, c_item.rd, 7'b0110011};
            finish_item(c_item);
        end
    endtask
endclass


class cpu_or_sequence extends uvm_sequence #(cpu_seq_item);
    `uvm_object_utils(cpu_or_sequence)
    cpu_seq_item c_item;
    int repeat_count = 15000;

    function new(string name = "cpu_or_sequence");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info("SEQ", $sformatf("START OR, random count=%0d", repeat_count), UVM_LOW)
        repeat (repeat_count) begin
            c_item = cpu_seq_item::type_id::create("c_item");
            start_item(c_item);
            c_item.command = OR;
            if (!c_item.randomize())
                `uvm_fatal("SEQ", "OR randomization failed")

            c_item.instr_code = {7'b0000000, c_item.rs2, c_item.rs1,
                                 3'b110, c_item.rd, 7'b0110011};
            finish_item(c_item);
        end
    endtask
endclass


class cpu_and_sequence extends uvm_sequence #(cpu_seq_item);
    `uvm_object_utils(cpu_and_sequence)
    cpu_seq_item c_item;
    int repeat_count = 15000;

    function new(string name = "cpu_and_sequence");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info("SEQ", $sformatf("START AND, random count=%0d", repeat_count), UVM_LOW)
        repeat (repeat_count) begin
            c_item = cpu_seq_item::type_id::create("c_item");
            start_item(c_item);
            c_item.command = AND;
            if (!c_item.randomize())
                `uvm_fatal("SEQ", "AND randomization failed")

            c_item.instr_code = {7'b0000000, c_item.rs2, c_item.rs1,
                                 3'b111, c_item.rd, 7'b0110011};
            finish_item(c_item);
        end
    endtask
endclass


class cpu_addi_sequence extends uvm_sequence #(cpu_seq_item);
    `uvm_object_utils(cpu_addi_sequence)
    cpu_seq_item c_item;
    int repeat_count = 65000;

    function new(string name = "cpu_addi_sequence");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info("SEQ", $sformatf("START ADDI, random count=%0d", repeat_count), UVM_LOW)
        repeat (repeat_count) begin
            c_item = cpu_seq_item::type_id::create("c_item");
            start_item(c_item);
            c_item.command = ADDI;
            if (!c_item.randomize())
                `uvm_fatal("SEQ", "ADDI randomization failed")

            c_item.instr_code = {c_item.imm, c_item.rs1, 3'b000,
                                 c_item.rd, 7'b0010011};
            finish_item(c_item);
        end
    endtask
endclass


class cpu_slti_sequence extends uvm_sequence #(cpu_seq_item);
    `uvm_object_utils(cpu_slti_sequence)
    cpu_seq_item c_item;
    int repeat_count = 65000;

    function new(string name = "cpu_slti_sequence");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info("SEQ", $sformatf("START SLTI, random count=%0d", repeat_count), UVM_LOW)
        repeat (repeat_count) begin
            c_item = cpu_seq_item::type_id::create("c_item");
            start_item(c_item);
            c_item.command = SLTI;
            if (!c_item.randomize())
                `uvm_fatal("SEQ", "SLTI randomization failed")

            c_item.instr_code = {c_item.imm, c_item.rs1, 3'b010,
                                 c_item.rd, 7'b0010011};
            finish_item(c_item);
        end
    endtask
endclass


class cpu_sltiu_sequence extends uvm_sequence #(cpu_seq_item);
    `uvm_object_utils(cpu_sltiu_sequence)
    cpu_seq_item c_item;
    int repeat_count = 65000;

    function new(string name = "cpu_sltiu_sequence");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info("SEQ", $sformatf("START SLTIU, random count=%0d", repeat_count), UVM_LOW)
        repeat (repeat_count) begin
            c_item = cpu_seq_item::type_id::create("c_item");
            start_item(c_item);
            c_item.command = SLTIU;
            if (!c_item.randomize())
                `uvm_fatal("SEQ", "SLTIU randomization failed")

            c_item.instr_code = {c_item.imm, c_item.rs1, 3'b011,
                                 c_item.rd, 7'b0010011};
            finish_item(c_item);
        end
    endtask
endclass


class cpu_xori_sequence extends uvm_sequence #(cpu_seq_item);
    `uvm_object_utils(cpu_xori_sequence)
    cpu_seq_item c_item;
    int repeat_count = 65000;

    function new(string name = "cpu_xori_sequence");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info("SEQ", $sformatf("START XORI, random count=%0d", repeat_count), UVM_LOW)
        repeat (repeat_count) begin
            c_item = cpu_seq_item::type_id::create("c_item");
            start_item(c_item);
            c_item.command = XORI;
            if (!c_item.randomize())
                `uvm_fatal("SEQ", "XORI randomization failed")

            c_item.instr_code = {c_item.imm, c_item.rs1, 3'b100,
                                 c_item.rd, 7'b0010011};
            finish_item(c_item);
        end
    endtask
endclass


class cpu_ori_sequence extends uvm_sequence #(cpu_seq_item);
    `uvm_object_utils(cpu_ori_sequence)
    cpu_seq_item c_item;
    int repeat_count = 65000;

    function new(string name = "cpu_ori_sequence");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info("SEQ", $sformatf("START ORI, random count=%0d", repeat_count), UVM_LOW)
        repeat (repeat_count) begin
            c_item = cpu_seq_item::type_id::create("c_item");
            start_item(c_item);
            c_item.command = ORI;
            if (!c_item.randomize())
                `uvm_fatal("SEQ", "ORI randomization failed")

            c_item.instr_code = {c_item.imm, c_item.rs1, 3'b110,
                                 c_item.rd, 7'b0010011};
            finish_item(c_item);
        end
    endtask
endclass


class cpu_andi_sequence extends uvm_sequence #(cpu_seq_item);
    `uvm_object_utils(cpu_andi_sequence)
    cpu_seq_item c_item;
    int repeat_count = 65000;

    function new(string name = "cpu_andi_sequence");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info("SEQ", $sformatf("START ANDI, random count=%0d", repeat_count), UVM_LOW)
        repeat (repeat_count) begin
            c_item = cpu_seq_item::type_id::create("c_item");
            start_item(c_item);
            c_item.command = ANDI;
            if (!c_item.randomize())
                `uvm_fatal("SEQ", "ANDI randomization failed")

            c_item.instr_code = {c_item.imm, c_item.rs1, 3'b111,
                                 c_item.rd, 7'b0010011};
            finish_item(c_item);
        end
    endtask
endclass


class cpu_slli_sequence extends uvm_sequence #(cpu_seq_item);
    `uvm_object_utils(cpu_slli_sequence)
    cpu_seq_item c_item;
    int repeat_count = 300;

    function new(string name = "cpu_slli_sequence");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info("SEQ", $sformatf("START SLLI, random count=%0d", repeat_count), UVM_LOW)
        repeat (repeat_count) begin
            c_item = cpu_seq_item::type_id::create("c_item");
            start_item(c_item);
            c_item.command = SLLI;
            if (!c_item.randomize())
                `uvm_fatal("SEQ", "SLLI randomization failed")

            c_item.instr_code = {7'b0000000, c_item.imm[4:0], c_item.rs1,
                                 3'b001, c_item.rd, 7'b0010011};
            finish_item(c_item);
        end
    endtask
endclass


class cpu_srli_sequence extends uvm_sequence #(cpu_seq_item);
    `uvm_object_utils(cpu_srli_sequence)
    cpu_seq_item c_item;
    int repeat_count = 300;

    function new(string name = "cpu_srli_sequence");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info("SEQ", $sformatf("START SRLI, random count=%0d", repeat_count), UVM_LOW)
        repeat (repeat_count) begin
            c_item = cpu_seq_item::type_id::create("c_item");
            start_item(c_item);
            c_item.command = SRLI;
            if (!c_item.randomize())
                `uvm_fatal("SEQ", "SRLI randomization failed")

            c_item.instr_code = {7'b0000000, c_item.imm[4:0], c_item.rs1,
                                 3'b101, c_item.rd, 7'b0010011};
            finish_item(c_item);
        end
    endtask
endclass


class cpu_srai_sequence extends uvm_sequence #(cpu_seq_item);
    `uvm_object_utils(cpu_srai_sequence)
    cpu_seq_item c_item;
    int repeat_count = 300;

    function new(string name = "cpu_srai_sequence");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info("SEQ", $sformatf("START SRAI, random count=%0d", repeat_count), UVM_LOW)
        repeat (repeat_count) begin
            c_item = cpu_seq_item::type_id::create("c_item");
            start_item(c_item);
            c_item.command = SRAI;
            if (!c_item.randomize())
                `uvm_fatal("SEQ", "SRAI randomization failed")

            c_item.instr_code = {7'b0100000, c_item.imm[4:0], c_item.rs1,
                                 3'b101, c_item.rd, 7'b0010011};
            finish_item(c_item);
        end
    endtask
endclass

class cpu_driver extends uvm_driver #(cpu_seq_item);
    `uvm_component_utils(cpu_driver)
    virtual cpu_if c_if;
    cpu_seq_item c_item;
    function new(string name = "cpu_driver", uvm_component c = null);
        super.new(name, c);
    endfunction
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual cpu_if)::get(this, "", "c_if", c_if))
            `uvm_fatal("DRV", "build_phase : can't access virtual interface")
    endfunction
virtual task run_phase(uvm_phase phase);
    forever begin
        seq_item_port.get_next_item(c_item);

        @(negedge c_if.clk);  
        c_if.instr_code <= c_item.instr_code;

        repeat (3) @(posedge c_if.clk);

        #2;  
        seq_item_port.item_done();
        end
    endtask
endclass

class cpu_monitor extends uvm_monitor;
    `uvm_component_utils(cpu_monitor)
    virtual cpu_if c_if;
    cpu_seq_item c_item;
    uvm_analysis_port #(cpu_seq_item) send;
    cpu_phase_e phase_ref = FETCH;
    function new(string name = "cpu_monitor", uvm_component c = null);
        super.new(name, c);
    endfunction
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual cpu_if)::get(this, "", "c_if", c_if))
            `uvm_fatal("MON", "build_phase : can't access virtual interface")
        send = new("WRITE", this);
    endfunction
    function cpu_command_e cpu_decode(logic [31:0] instr);

        
        cpu_decode = ERROR;

        case (instr[6:0])

            // R-type
            7'h33: begin
                case ({instr[31:25], instr[14:12]})
                    10'h000: cpu_decode = ADD;
                    10'h100: cpu_decode = SUB;
                    10'h001: cpu_decode = SLL;
                    10'h002: cpu_decode = SLT;
                    10'h003: cpu_decode = SLTU;
                    10'h004: cpu_decode = XOR;
                    10'h005: cpu_decode = SRL;
                    10'h105: cpu_decode = SRA;
                    10'h006: cpu_decode = OR;
                    10'h007: cpu_decode = AND;
                endcase
            end

            // I-type
            7'h13: begin
                case (instr[14:12])
                    3'b000: cpu_decode = ADDI;
                    3'b010: cpu_decode = SLTI;
                    3'b011: cpu_decode = SLTIU;
                    3'b100: cpu_decode = XORI;
                    3'b110: cpu_decode = ORI;
                    3'b111: cpu_decode = ANDI;

                    3'b001: begin
                        if (instr[31:25] == 7'h00)
                            cpu_decode = SLLI;
                    end

                    3'b101: begin
                        if (instr[31:25] == 7'h00)
                            cpu_decode = SRLI;
                        else if (instr[31:25] == 7'h20)
                            cpu_decode = SRAI;
                    end
                endcase
            end

        endcase
    endfunction
    virtual task run_phase(uvm_phase phase);
        forever begin
            @(c_if.mon_cb);
            c_item = cpu_seq_item::type_id::create("c_item");
            c_item.rst_n = c_if.mon_cb.rst_n;
            c_item.sample_phase = phase_ref;
            c_item.instr_code = c_if.mon_cb.instr_code;
            c_item.command = cpu_decode(c_item.instr_code);
            c_item.instr_addr_before = c_if.mon_cb.instr_addr;
            c_item.alu_control = c_if.mon_cb.alu_control;
            c_item.dwe = c_if.mon_cb.dwe;
            c_item.rf_we = c_if.mon_cb.rf_we;
            c_item.alusrc_sel = c_if.mon_cb.alusrc_sel;
            c_item.itype = c_if.mon_cb.itype;
            #1;
            c_item.instr_addr = c_if.instr_addr;
            c_item.daddr = c_if.daddr;
            c_item.dwdata = c_if.dwdata;

            `uvm_info("MON", c_item.convert2string(), UVM_HIGH)
            send.write(c_item);
            if (!c_item.rst_n) phase_ref = FETCH;
            else
                case (phase_ref)
                    FETCH:   phase_ref = DECODE;
                    DECODE:  phase_ref = EXECUTE;
                    EXECUTE: phase_ref = FETCH;
                endcase
        end
    endtask
endclass

class cpu_agent extends uvm_agent;
    `uvm_component_utils(cpu_agent)
    cpu_driver cpu_drv;
    cpu_monitor cpu_mon;
    uvm_sequencer #(cpu_seq_item) cpu_sqr;
    function new(string name = "cpu_agent", uvm_component c = null);
        super.new(name, c);
    endfunction
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        cpu_drv = cpu_driver::type_id::create("drv", this);
        cpu_mon = cpu_monitor::type_id::create("mon", this);
        cpu_sqr = uvm_sequencer#(cpu_seq_item)::type_id::create("sqr", this);
    endfunction
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        cpu_drv.seq_item_port.connect(cpu_sqr.seq_item_export);
    endfunction
endclass

class cpu_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(cpu_scoreboard)

    uvm_analysis_imp #(cpu_seq_item, cpu_scoreboard) recv;

    bit [31:0] rf_ref[0:31];
    logic [31:0] instr_ref;
    int pass_cnt, fail_cnt;

    function new(
        string name = "cpu_scoreboard",
        uvm_component c = null
    );
        super.new(name, c);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        recv = new("READ", this);

        rf_ref[0] = 0;
    endfunction

    virtual function void write(cpu_seq_item c_item);
        bit [6:0] opcode, funct7;
        bit [2:0] funct3;
        bit [3:0] alu_ref;
        bit [31:0] a, b, result_ref;
        int rs1, rs2, rd;

        if ((c_item.rst_n === 1'b1) &&
            (c_item.sample_phase == EXECUTE)) begin

            instr_ref = c_item.instr_code;

            opcode = instr_ref[6:0];
            funct3 = instr_ref[14:12];
            funct7 = instr_ref[31:25];
            rs1    = instr_ref[19:15];
            rs2    = instr_ref[24:20];
            rd     = instr_ref[11:7];

            // rs1
            a = rf_ref[rs1];

            if (opcode == 7'h33)
                b = rf_ref[rs2];
            else
                b = {{20{instr_ref[31]}}, instr_ref[31:20]};

            // rs2
            alu_ref = {1'b0, funct3};

            if (opcode == 7'h33 || funct3 == 3'b101)
                alu_ref = {instr_ref[30], funct3};

            // alu_result
            case (funct3)
                3'b000: begin
                    if (opcode == 7'h33 && funct7 == 7'h20)
                        result_ref = a - b;  // SUB
                    else
                        result_ref = a + b;  // ADD, ADDI
                end

                3'b001:
                    result_ref = a << b[4:0];  // SLL, SLLI

                3'b010:
                    result_ref =
                        ($signed(a) < $signed(b)) ? 1 : 0;  // SLT, SLTI

                3'b011:
                    result_ref = (a < b) ? 1 : 0;  // SLTU, SLTIU

                3'b100:
                    result_ref = a ^ b;  // XOR, XORI

                3'b101: begin
                    if (funct7 == 7'h20)
                        result_ref = $signed(a) >>> b[4:0];  // SRA, SRAI
                    else
                        result_ref = a >> b[4:0];  // SRL, SRLI
                end

                3'b110:
                    result_ref = a | b;  // OR, ORI

                3'b111:
                    result_ref = a & b;  // AND, ANDI
            endcase

            // pass fail
            if ((c_item.rf_we === 1'b1) &&
                (c_item.alusrc_sel === (opcode == 7'h13)) &&
                (c_item.alu_control === alu_ref) &&
                (c_item.daddr === result_ref)) begin

                pass_cnt++;

                `uvm_info("SCB", $sformatf(
                    "PASS instr = %08h, rd = x%0d, expected_alu_result = %08h, daddr = %08h",
                    instr_ref, rd, result_ref, c_item.daddr
                ), UVM_HIGH)

            end else begin
                fail_cnt++;

                `uvm_error("SCB", $sformatf(
                    "FAIL instr=%08h, rd=x%0d, expected_alu_result = %08h, daddr = %08h, rf_we=%b(expected 1), alusrc=%b(expected %b) alu_control = %b(expected %b)",
                    instr_ref, rd, result_ref, c_item.daddr,
                    c_item.rf_we,
                    c_item.alusrc_sel, (opcode == 7'h13),
                    c_item.alu_control, alu_ref
                ))
            end


            if (rd != 0) begin
                rf_ref[rd] = result_ref;
            end
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);

        `uvm_info("SCB", $sformatf(
            "PASS = %0d FAIL = %0d",
            pass_cnt,
            fail_cnt
        ), UVM_NONE)
    endfunction
endclass



class cpu_coverage extends uvm_subscriber #(cpu_seq_item);
    `uvm_component_utils(cpu_coverage)

    cpu_seq_item c_item;
    bit execute_sample, R_type, I_type, shift_command;

    covergroup cpu_cg;
        option.per_instance = 1;

        cp_reset: coverpoint c_item.rst_n {
            bins rst_n_0 = {0};
            bins rst_n_1 = {1};
        }


        cp_r_command: coverpoint c_item.command
            iff (execute_sample && R_type) {
            bins instructions[] = {[ADD : AND]};
        }


        cp_i_command: coverpoint c_item.command
            iff (execute_sample && I_type && !shift_command) {
            bins instructions[] = {[ADDI : ANDI]};
        }

        cp_i_shift_command: coverpoint c_item.command
            iff (execute_sample && I_type && shift_command) {
            bins instructions[] = {[SLLI : SRAI]};
        }

        cp_rs1: coverpoint c_item.instr_code[19:15]
            iff (execute_sample) {
            bins regs[] = {[0 : 31]};
        }

        cp_rs2: coverpoint c_item.instr_code[24:20]
            iff (execute_sample && R_type) {
            bins regs[] = {[0 : 31]};
        }

        cp_rd: coverpoint c_item.instr_code[11:7]
            iff (execute_sample) {
            bins regs[] = {[0 : 31]};
        }

        cp_imm: coverpoint $signed(c_item.instr_code[31:20])
            iff (execute_sample && I_type && !shift_command) {
            bins values[] = {[-2048 : 2047]};
        }

        cp_i_shift_imm: coverpoint c_item.instr_code[24:20]
            iff (execute_sample && I_type && shift_command) {
            bins values[] = {[0 : 31]};
        }

        cx_r_rs1_rs2: cross cp_r_command, cp_rs1, cp_rs2
            iff (execute_sample && R_type);

        cx_i_imm: cross cp_i_command, cp_imm
            iff (execute_sample && I_type && !shift_command);

        cx_i_shift_imm: cross cp_i_shift_command, cp_i_shift_imm
            iff (execute_sample && I_type && shift_command);
        
        cx_r_rd: cross cp_r_command, cp_rd
            iff (execute_sample && R_type);

        cx_i_rd: cross cp_i_command, cp_rd
            iff (execute_sample && I_type && !shift_command);
            
        cx_i_shift_rd: cross cp_i_shift_command, cp_rd
            iff (execute_sample && I_type && shift_command);


    endgroup

    function new(
        string name = "cpu_coverage",
        uvm_component c = null
    );
        super.new(name, c);
        cpu_cg = new();
    endfunction

    virtual function void write(cpu_seq_item t);
        c_item = t;

        execute_sample = (t.rst_n === 1'b1) &&
                         (t.sample_phase == EXECUTE);

        R_type = (t.instr_code[6:0] == 7'h33);
        I_type = (t.instr_code[6:0] == 7'h13);

        shift_command = t.command inside {SLLI, SRLI, SRAI};

        cpu_cg.sample();
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);

        `uvm_info("COV", $sformatf("************************** rv32i_cpu Coverage Report **************************"), UVM_NONE)
        
        `uvm_info("COV", $sformatf(
            "Overall = %.1f%% Reset = %.1f%%",
            cpu_cg.get_inst_coverage(),
            cpu_cg.cp_reset.get_inst_coverage()
        ), UVM_NONE)

        `uvm_info("COV", $sformatf(
            "R commands = %.1f%% I commands = %.1f%% I shift commands = %.1f%%",
            cpu_cg.cp_r_command.get_inst_coverage(),
            cpu_cg.cp_i_command.get_inst_coverage(),
            cpu_cg.cp_i_shift_command.get_inst_coverage()
        ), UVM_NONE)

        `uvm_info("COV", $sformatf(
            "RS1 = %.1f%% RS2 = %.1f%% RD = %.1f%%",
            cpu_cg.cp_rs1.get_inst_coverage(),
            cpu_cg.cp_rs2.get_inst_coverage(),
            cpu_cg.cp_rd.get_inst_coverage()
        ), UVM_NONE)

        `uvm_info("COV", $sformatf(
            "R command x rs1 x rs2 = %.1f%%",
            cpu_cg.cx_r_rs1_rs2.get_inst_coverage()
        ), UVM_NONE)

        `uvm_info("COV", $sformatf(
            "I command x imm = %.1f%% I shift command x imm = %.1f%%",
            cpu_cg.cx_i_imm.get_inst_coverage(),
            cpu_cg.cx_i_shift_imm.get_inst_coverage()
        ), UVM_NONE)

        `uvm_info("COV", $sformatf(
            "R command x rd = %.1f%%, I command x rd = %.1f%%, I shift command x rd = %.1f%%",
            cpu_cg.cx_r_rd.get_inst_coverage(),
            cpu_cg.cx_i_rd.get_inst_coverage(),
            cpu_cg.cx_i_shift_rd.get_inst_coverage()
        ), UVM_NONE)
        
        `uvm_info("COV", $sformatf("*******************************************************************************"), UVM_NONE)
    endfunction
endclass

class cpu_environment extends uvm_env;
    `uvm_component_utils(cpu_environment)
    cpu_agent cpu_agt;
    cpu_scoreboard cpu_scb;
    cpu_coverage cpu_cov;
    function new(string name = "cpu_environment", uvm_component c = null);
        super.new(name, c);
    endfunction
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        cpu_agt = cpu_agent::type_id::create("AGT", this);
        cpu_scb = cpu_scoreboard::type_id::create("SCB", this);
        cpu_cov = cpu_coverage::type_id::create("COV", this);
    endfunction
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        cpu_agt.cpu_mon.send.connect(cpu_scb.recv);
        cpu_agt.cpu_mon.send.connect(cpu_cov.analysis_export);
    endfunction
endclass

class cpu_test extends uvm_test;
    `uvm_component_utils(cpu_test)
    cpu_init_sequence init_seq;
    cpu_add_sequence add_seq;
    cpu_sub_sequence sub_seq;
    cpu_sll_sequence sll_seq;
    cpu_slt_sequence slt_seq;
    cpu_sltu_sequence sltu_seq;
    cpu_xor_sequence xor_seq;
    cpu_srl_sequence srl_seq;
    cpu_sra_sequence sra_seq;
    cpu_or_sequence or_seq;
    cpu_and_sequence and_seq;
    cpu_addi_sequence addi_seq;
    cpu_slti_sequence slti_seq;
    cpu_sltiu_sequence sltiu_seq;
    cpu_xori_sequence xori_seq;
    cpu_ori_sequence ori_seq;
    cpu_andi_sequence andi_seq;
    cpu_slli_sequence slli_seq;
    cpu_srli_sequence srli_seq;
    cpu_srai_sequence srai_seq;
    cpu_environment cpu_env;

    function new(string name = "cpu_test", uvm_component c = null);
        super.new(name, c);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        init_seq = cpu_init_sequence::type_id::create("init_seq", this);
        add_seq = cpu_add_sequence::type_id::create("add_seq", this);
        sub_seq = cpu_sub_sequence::type_id::create("sub_seq", this);
        sll_seq = cpu_sll_sequence::type_id::create("sll_seq", this);
        slt_seq = cpu_slt_sequence::type_id::create("slt_seq", this);
        sltu_seq = cpu_sltu_sequence::type_id::create("sltu_seq", this);
        xor_seq = cpu_xor_sequence::type_id::create("xor_seq", this);
        srl_seq = cpu_srl_sequence::type_id::create("srl_seq", this);
        sra_seq = cpu_sra_sequence::type_id::create("sra_seq", this);
        or_seq = cpu_or_sequence::type_id::create("or_seq", this);
        and_seq = cpu_and_sequence::type_id::create("and_seq", this);
        addi_seq = cpu_addi_sequence::type_id::create("addi_seq", this);
        slti_seq = cpu_slti_sequence::type_id::create("slti_seq", this);
        sltiu_seq = cpu_sltiu_sequence::type_id::create("sltiu_seq", this);
        xori_seq = cpu_xori_sequence::type_id::create("xori_seq", this);
        ori_seq = cpu_ori_sequence::type_id::create("ori_seq", this);
        andi_seq = cpu_andi_sequence::type_id::create("andi_seq", this);
        slli_seq = cpu_slli_sequence::type_id::create("slli_seq", this);
        srli_seq = cpu_srli_sequence::type_id::create("srli_seq", this);
        srai_seq = cpu_srai_sequence::type_id::create("srai_seq", this);
        cpu_env = cpu_environment::type_id::create("env", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        init_seq.start(cpu_env.cpu_agt.cpu_sqr);
        add_seq.start(cpu_env.cpu_agt.cpu_sqr);
        init_seq.start(cpu_env.cpu_agt.cpu_sqr);
        sub_seq.start(cpu_env.cpu_agt.cpu_sqr);
        init_seq.start(cpu_env.cpu_agt.cpu_sqr);
        sll_seq.start(cpu_env.cpu_agt.cpu_sqr);
        init_seq.start(cpu_env.cpu_agt.cpu_sqr);
        slt_seq.start(cpu_env.cpu_agt.cpu_sqr);
        init_seq.start(cpu_env.cpu_agt.cpu_sqr);
        sltu_seq.start(cpu_env.cpu_agt.cpu_sqr);
        init_seq.start(cpu_env.cpu_agt.cpu_sqr);
        xor_seq.start(cpu_env.cpu_agt.cpu_sqr);
        init_seq.start(cpu_env.cpu_agt.cpu_sqr);
        srl_seq.start(cpu_env.cpu_agt.cpu_sqr);
        init_seq.start(cpu_env.cpu_agt.cpu_sqr);
        sra_seq.start(cpu_env.cpu_agt.cpu_sqr);
        init_seq.start(cpu_env.cpu_agt.cpu_sqr);
        or_seq.start(cpu_env.cpu_agt.cpu_sqr);
        init_seq.start(cpu_env.cpu_agt.cpu_sqr);
        and_seq.start(cpu_env.cpu_agt.cpu_sqr);
        init_seq.start(cpu_env.cpu_agt.cpu_sqr);
        addi_seq.start(cpu_env.cpu_agt.cpu_sqr);
        init_seq.start(cpu_env.cpu_agt.cpu_sqr);
        slti_seq.start(cpu_env.cpu_agt.cpu_sqr);
        init_seq.start(cpu_env.cpu_agt.cpu_sqr);
        sltiu_seq.start(cpu_env.cpu_agt.cpu_sqr);
        init_seq.start(cpu_env.cpu_agt.cpu_sqr);
        xori_seq.start(cpu_env.cpu_agt.cpu_sqr);
        init_seq.start(cpu_env.cpu_agt.cpu_sqr);
        ori_seq.start(cpu_env.cpu_agt.cpu_sqr);
        init_seq.start(cpu_env.cpu_agt.cpu_sqr);
        andi_seq.start(cpu_env.cpu_agt.cpu_sqr);
        init_seq.start(cpu_env.cpu_agt.cpu_sqr);
        slli_seq.start(cpu_env.cpu_agt.cpu_sqr);
        init_seq.start(cpu_env.cpu_agt.cpu_sqr);
        srli_seq.start(cpu_env.cpu_agt.cpu_sqr);
        init_seq.start(cpu_env.cpu_agt.cpu_sqr);
        srai_seq.start(cpu_env.cpu_agt.cpu_sqr);
        phase.drop_objection(this);
    endtask
endclass

module tb_rv32i_uvm;
    logic clk = 0;
    always #5 clk = ~clk;
    cpu_if c_if (clk);

    rv32i_cpu dut (
        .clk(clk),
        .rst_n(c_if.rst_n),
        .instr_code(c_if.instr_code),
        .instr_addr(c_if.instr_addr),
        .alu_control(c_if.alu_control),
        .daddr(c_if.daddr),
        .dwe(c_if.dwe),
        .rf_we(c_if.rf_we),
        .alusrc_sel(c_if.alusrc_sel),
        .itype(c_if.itype)
    );

    initial begin
        $fsdbDumpfile("wave.fsdb");
        $fsdbDumpvars(0, tb_rv32i_uvm);
    end

    initial begin
        uvm_config_db#(virtual cpu_if)::set(null, "*", "c_if", c_if);
        run_test("cpu_test");
    end

endmodule
