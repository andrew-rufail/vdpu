module hbm_port #(
    parameter int BURST_LEN = 256,
    parameter int ID_WIDTH = 20,
    parameter int ADDR_WIDTH = 34,
    parameter int DATA_WIDTH = 256
)(
    input  logic clk,
    input  logic nrst,

    input  logic start,
    output logic done,
    output logic valid_out,

    input  logic [ADDR_WIDTH-1:0] start_addr,
    input  logic [ADDR_WIDTH-1:0] end_addr,
    output logic [DATA_WIDTH-1:0] data_out,

    //AXI Read Address Channel
    output logic [ID_WIDTH-1:0]    m_axi_arid,
    output logic [ADDR_WIDTH-1:0]  m_axi_araddr,
    output logic [7:0]             m_axi_arlen,
    output logic [2:0]             m_axi_arsize,
    output logic [1:0]             m_axi_arburst,
    output logic                   m_axi_arlock,
    output logic [3:0]             m_axi_arcache,
    output logic [3:0]             m_axi_arprot,
    output logic [3:0]             m_axi_arqos,
    output logic                   m_axi_arvalid,
    input  logic                   m_axi_arready,

    //AXI Read Data Channel
    input  logic [ID_WIDTH-1:0]    m_axi_rid,
    input  logic [DATA_WIDTH-1:0]  m_axi_rdata,
    input  logic [1:0]             m_axi_rresp,
    input  logic                   m_axi_rlast,
    input  logic                   m_axi_rvalid,
    output logic                   m_axi_rready,

    //AXI Write Channels (Disabled/Tied-off)
    output logic [ID_WIDTH-1:0]    m_axi_awid,
    output logic [ADDR_WIDTH-1:0]  m_axi_awaddr,
    output logic [7:0]             m_axi_awlen,
    output logic [2:0]             m_axi_awsize,
    output logic [1:0]             m_axi_awburst,
    output logic                   m_axi_awvalid,
    input  logic                   m_axi_awready,
    output logic [DATA_WIDTH-1:0]  m_axi_wdata,
    output logic [(DATA_WIDTH/8)-1:0] m_axi_wstrb,
    output logic                   m_axi_wlast,
    output logic                   m_axi_wvalid,
    input  logic                   m_axi_wready,
    input  logic [ID_WIDTH-1:0]    m_axi_bid,
    input  logic [1:0]             m_axi_bresp,
    input  logic                   m_axi_bvalid,
    output logic                   m_axi_bready
);

    localparam int DATA_BYTES  = DATA_WIDTH / 8;
    localparam int BURST_BYTES = BURST_LEN * DATA_BYTES;

    typedef enum logic [1:0] {IDLE, SEND_AR, READ, DONE} state_t;
    state_t state;

    logic [ADDR_WIDTH-1:0] curr_addr;

    // Constant AXI fields
    assign m_axi_arid    = '0;
    assign m_axi_arlen   = 8'(BURST_LEN - 1);
    assign m_axi_arsize  = 3'b101;     // 32 bytes (for 256-bit bus)
    assign m_axi_arburst = 2'b01;      // INCR
    assign m_axi_arlock  = 1'b0;
    assign m_axi_arcache = 4'b0011;
    assign m_axi_arprot  = 3'b000;
    assign m_axi_arqos   = 4'b0000;

    // Write Channel Tie-offs
    assign m_axi_awid    = '0;
    assign m_axi_awaddr  = '0;
    assign m_axi_awlen   = '0;
    assign m_axi_awsize  = 3'b101;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awvalid = 1'b0;
    assign m_axi_wdata   = '0;
    assign m_axi_wstrb   = '1;
    assign m_axi_wlast   = 1'b0;
    assign m_axi_wvalid  = 1'b0;
    assign m_axi_bready  = 1'b1;

    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            state <= IDLE;
            curr_addr <= '0;
            m_axi_arvalid <= 1'b0;
            m_axi_rready <= 1'b0;
            done <= 1'b0;
            valid_out <= 1'b0;
            m_axi_araddr <= '0;
            data_out <= '0;
        end else begin
            valid_out <= 1'b0;

            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        curr_addr <= start_addr;
                        state <= SEND_AR;
                    end
                end

                SEND_AR: begin
                    m_axi_araddr <= curr_addr;
                    m_axi_arvalid <= 1'b1;

                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready <= 1'b1;
                        state <= READ;
                    end
                end

                READ: begin
                    if (m_axi_rvalid) begin
                        data_out  <= m_axi_rdata;
                        valid_out <= 1'b1;
                    end

                    if (m_axi_rvalid && m_axi_rlast) begin
                        if (curr_addr + BURST_BYTES >= end_addr) begin
                            m_axi_rready <= 1'b0;
                            state <= DONE;
                        end else begin
                            curr_addr <= curr_addr + BURST_BYTES;
                            m_axi_rready <= 1'b0; 
                            state <= SEND_AR;
                        end
                    end
                end

                DONE: begin
                    done <= 1'b1;
                    if (!start) state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule