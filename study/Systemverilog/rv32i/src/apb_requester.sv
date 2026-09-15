`timescale 1ns / 1ps

module apb_requester (
    // with CPU
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] bus_addr,
    input  logic [31:0] bus_wdata,
    input  logic        transfer,
    input  logic        bus_we,
    output logic        ready,
    output logic [31:0] bus_rdata,
    // apb interface
    input  logic        PREADY0,    // APB RAM
    input  logic        PREADY1,    // GPI
    input  logic        PREADY2,    // GPO
    input  logic        PREADY3,    // GPIO
    input  logic        PREADY4,    // FND
    input  logic        PREADY5,    // UART
    input  logic        PREADY6,    // 
    input  logic [31:0] PRDATA0,
    input  logic [31:0] PRDATA1,
    input  logic [31:0] PRDATA2,
    input  logic [31:0] PRDATA3,
    input  logic [31:0] PRDATA4,
    input  logic [31:0] PRDATA5,
    input  logic [31:0] PRDATA6,
    output logic [31:0] PADDR,
    output logic [31:0] PWDATA,
    output logic        PWRITE,
    output logic        PENABLE,
    output logic        PSEL0,
    output logic        PSEL1,
    output logic        PSEL2,
    output logic        PSEL3,
    output logic        PSEL4,
    output logic        PSEL5,
    output logic        PSEL6
);

    typedef enum logic [1:0] {
        IDLE,
        SETUP,
        ACCESS
    } state_e;

    state_e c_state, n_state;
    logic addr_dec_en;  // address decoder enable
    logic [2:0] mux_sel;

    logic [31:0] temp_PADDR, temp_PADDR_next;
    logic [31:0] temp_PWDATA, temp_PWDATA_next;
    logic temp_PWRITE, temp_PWRITE_next;

    // 미결정(undecoded) 주소는 어떤 completer 도 PREADYx 를 assert 하지 않으므로
    // mux_ready 가 영원히 0 -> ACCESS 상태에서 못 빠져나오는 걸 막기 위한 timeout.
    localparam int ACCESS_TIMEOUT_CYCLES = 16;
    logic [4:0] access_cnt, access_cnt_next;
    logic access_timeout;
    logic mux_ready;
    logic [31:0] mux_rdata;

    assign PADDR  = {4'b0000, temp_PADDR[27:0]};
    assign PWDATA = temp_PWDATA;
    assign PWRITE = temp_PWRITE;
    assign ready     = mux_ready | access_timeout;
    assign bus_rdata = mux_rdata;


    always_ff @(posedge clk) begin
        if (!rst_n) begin
            c_state <= IDLE;
            temp_PADDR <= 32'h0;
            temp_PWDATA <= 32'h0;
            temp_PWRITE <= 1'b0;
            access_cnt <= '0;
        end else begin
            c_state <= n_state;
            temp_PADDR <= temp_PADDR_next;
            temp_PWDATA <= temp_PWDATA_next;
            temp_PWRITE <= temp_PWRITE_next;
            access_cnt <= access_cnt_next;
        end
    end

    always_comb begin
        access_cnt_next = access_cnt;
        access_timeout  = 1'b0;
        if (c_state == ACCESS && !mux_ready) begin
            if (access_cnt == ACCESS_TIMEOUT_CYCLES - 1) begin
                access_timeout  = 1'b1;
                access_cnt_next = '0;
            end else begin
                access_cnt_next = access_cnt + 1'b1;
            end
        end else begin
            access_cnt_next = '0;
        end
    end

    always_comb begin
        n_state = c_state;
        temp_PADDR_next = temp_PADDR;
        temp_PWDATA_next = temp_PWDATA;
        temp_PWRITE_next = temp_PWRITE;

        addr_dec_en = 1'b0;
        PENABLE = 1'b0;
        case (c_state)
            IDLE: begin
                if (transfer) begin
                    temp_PADDR_next = bus_addr;
                    temp_PWDATA_next = bus_wdata;
                    temp_PWRITE_next = bus_we;
                    n_state = SETUP;
                end
            end
            SETUP: begin
                addr_dec_en = 1'b1;
                PENABLE = 1'b0;
                n_state = ACCESS;
            end
            ACCESS: begin
                addr_dec_en = 1'b1;
                PENABLE = 1'b1;
                if (ready) n_state = IDLE;
            end
        endcase
    end

    address_decoder U_APB_DECODER (
        .enable (addr_dec_en),
        .mux_sel(mux_sel),
        .PADDR  (temp_PADDR),
        .*
    );


    apb_mux U_APB_MUX (
        .sel      (mux_sel),
        .ready    (mux_ready),
        .bus_rdata(mux_rdata),
        .*
    );

    // APB Requester FSM

endmodule

module address_decoder (
    input  logic        enable,
    output logic [ 2:0] mux_sel,
    // APB interface
    input  logic [31:0] PADDR,
    output logic        PSEL0,
    output logic        PSEL1,
    output logic        PSEL2,
    output logic        PSEL3,
    output logic        PSEL4,
    output logic        PSEL5,
    output logic        PSEL6
);

    always_comb begin
        PSEL0   = 1'b0;
        PSEL1   = 1'b0;
        PSEL2   = 1'b0;
        PSEL3   = 1'b0;
        PSEL4   = 1'b0;
        PSEL5   = 1'b0;
        PSEL6   = 1'b0;
        mux_sel = 3'b000;
        if (enable)
            case (PADDR[31:28])
                4'b0001: begin  // APB RAM
                    PSEL0   = 1'b1;
                    mux_sel = 3'b000;

                end
                4'b0010: begin  // Periphral, GPI, GPO, GPIO, FND, UART...
                    case (PADDR[11:8])
                        4'b0000: begin
                            PSEL1   = 1'b1;
                            mux_sel = 3'b001;
                        end
                        4'b0001: begin
                            PSEL2   = 1'b1;
                            mux_sel = 3'b010;
                        end
                        4'b0010: begin
                            PSEL3   = 1'b1;
                            mux_sel = 3'b011;
                        end
                        4'b0011: begin
                            PSEL4   = 1'b1;
                            mux_sel = 3'b100;
                        end
                        4'b0100: begin
                            PSEL5   = 1'b1;
                            mux_sel = 3'b101;
                        end
                        4'b0101: begin
                            PSEL6   = 1'b1;
                            mux_sel = 3'b110;
                        end
                    endcase
                end
            endcase
    end

endmodule
module apb_mux (
    input  logic [ 2:0] sel,
    output logic [31:0] bus_rdata,
    output logic        ready,
    // APB interface
    input  logic [31:0] PRDATA0,
    input  logic [31:0] PRDATA1,
    input  logic [31:0] PRDATA2,
    input  logic [31:0] PRDATA3,
    input  logic [31:0] PRDATA4,
    input  logic [31:0] PRDATA5,
    input  logic [31:0] PRDATA6,
    input  logic        PREADY0,
    input  logic        PREADY1,
    input  logic        PREADY2,
    input  logic        PREADY3,
    input  logic        PREADY4,
    input  logic        PREADY5,
    input  logic        PREADY6
);

    always_comb begin
        bus_rdata = PRDATA0;
        ready = PREADY0;
        case (sel)
            3'b000: begin
                bus_rdata = PRDATA0;
                ready = PREADY0;
            end
            3'b001: begin
                bus_rdata = PRDATA1;
                ready = PREADY1;
            end
            3'b010: begin
                bus_rdata = PRDATA2;
                ready = PREADY2;
            end
            3'b011: begin
                bus_rdata = PRDATA3;
                ready = PREADY3;
            end
            3'b100: begin
                bus_rdata = PRDATA4;
                ready = PREADY4;
            end
            3'b101: begin
                bus_rdata = PRDATA5;
                ready = PREADY5;
            end
            3'b110: begin
                bus_rdata = PRDATA6;
                ready = PREADY6;
            end
        endcase
    end

endmodule
