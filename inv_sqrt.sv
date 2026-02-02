module inv_sqrt(
    input logic clk,
    input logic nrst,
    input logic [31:0] x_in,
    input logic valid_in,
    output logic [31:0] y_out,
    output logic valid_out
);
    localparam logic [31:0] MAGIC = 32'h5F3759DF;
    localparam logic [31:0] FP_1_5 = 32'h3FC00000;
    localparam int MUL_L = 8; 
    localparam int ADD_L = 11;

    logic [31:0] y0_seed;
    logic v0;

    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            y0_seed <= 32'b0;
            v0      <= 1'b0;
        end else begin
            v0      <= valid_in;
            y0_seed <= MAGIC - {1'b0, x_in[31:1]};
        end
    end

    logic [31:0] y0_sq;
    logic mul1_a_tready, mul1_b_tready;

    fp32_mult mul1 (
        .aclk(clk),
        .s_axis_a_tvalid(v0),
       // .s_axis_a_tready(mul1_a_tready),
        .s_axis_a_tdata(y0_seed),
        .s_axis_b_tvalid(v0),
        //.s_axis_b_tready(mul1_b_tready),
        .s_axis_b_tdata(y0_seed),
        .m_axis_result_tdata(y0_sq)
        //.m_axis_result_tready(1'b1)
    );

    logic v1;
    delay_pipe #(.WIDTH(1), .DEPTH(MUL_L)) vpipe1 (
        .clk(clk), .nrst(nrst), .d(v0), .q(v1)
    );

    logic [31:0] x_delayed;
    delay_pipe #(.WIDTH(32), .DEPTH(MUL_L+1)) d1 (
        .clk(clk), .nrst(nrst), .d(x_in), .q(x_delayed)
    );

    logic [31:0] x_y0_sq;
    logic mul2_a_tready, mul2_b_tready;

    fp32_mult mul2 (
        .aclk(clk),
        .s_axis_a_tvalid(v1),
        //.s_axis_a_tready(mul2_a_tready),
        .s_axis_a_tdata(y0_sq),
        .s_axis_b_tvalid(v1),
    //  .s_axis_b_tready(mul2_b_tready),
        .s_axis_b_tdata(x_delayed),
        .m_axis_result_tdata(x_y0_sq)
    //    .m_axis_result_tready(1'b1)
    );

    logic v2;
    delay_pipe #(.WIDTH(1), .DEPTH(MUL_L)) vpipe2 (
        .clk(clk), .nrst(nrst), .d(v1), .q(v2)
    );

    logic [31:0] half_val;
    assign half_val =
        (x_y0_sq[30:23] != 8'd0)
            ? {1'b0, x_y0_sq[30:23] - 8'd1, x_y0_sq[22:0]}
            : 32'b0;

    logic [31:0] scaler;
    logic sub_a_tready, sub_b_tready;

    fp32_add sub1 (
        .aclk(clk),
        .s_axis_a_tvalid(v2),
       // .s_axis_a_tready(sub_a_tready),
        .s_axis_a_tdata(FP_1_5),
        .s_axis_b_tvalid(v2),
        //.s_axis_b_tready(sub_b_tready),
        .s_axis_b_tdata(half_val),
        .s_axis_operation_tvalid(v2),
        .s_axis_operation_tdata(8'h01),
        .m_axis_result_tdata(scaler)
        //.m_axis_result_tready(1'b1)
    );

    logic v3;
    delay_pipe #(.WIDTH(1), .DEPTH(ADD_L)) vpipe3 (
        .clk(clk), .nrst(nrst), .d(v2), .q(v3)
    );

    logic [31:0] y0_aligned;
    delay_pipe #(.WIDTH(32), .DEPTH(MUL_L + MUL_L + ADD_L)) d2 (
        .clk(clk), .nrst(nrst), .d(y0_seed), .q(y0_aligned)
    );

    logic mul3_a_tready, mul3_b_tready;

    fp32_mult mul3 (
        .aclk(clk),
        .s_axis_a_tvalid(v3),
        //.s_axis_a_tready(mul3_a_tready),
        .s_axis_a_tdata(y0_aligned),
        .s_axis_b_tvalid(v3),
        //.s_axis_b_tready(mul3_b_tready),
        .s_axis_b_tdata(scaler),
        .m_axis_result_tdata(y_out)
        //.m_axis_result_tready(1'b1)
    );

    delay_pipe #(.WIDTH(1), .DEPTH(MUL_L)) vpipe4 (
        .clk(clk), .nrst(nrst), .d(v3), .q(valid_out)
    );

endmodule



module delay_pipe #(
    parameter WIDTH = 32,
    parameter DEPTH = 1
)(
    input  logic clk,
    input  logic nrst,
    input  logic [WIDTH-1:0] d,
    output logic [WIDTH-1:0] q
);
    generate
        if (DEPTH == 0) begin : zero_depth
            assign q = d;
        end else begin : shift_reg_gen
            logic [WIDTH-1:0] shift_reg [0:DEPTH-1];
            always_ff @(posedge clk or negedge nrst) begin
                if (!nrst) begin
                    for (int i = 0; i < DEPTH; i++) shift_reg[i] <= '0;
                end else begin
                    shift_reg[0] <= d;
                    for (int i = 1; i < DEPTH; i++) shift_reg[i] <= shift_reg[i-1];
                end
            end
            assign q = shift_reg[DEPTH-1];
        end
    endgenerate
endmodule