module norm#(
    parameter id_width = 20
)(
    input  logic clk,
    input  logic nrst,
    input  logic valid_in,

    // Precomputed sum of dot products: sum(x_i * x_i)
    input  logic signed [31:0] dot_sum,

    input  logic [id_width-1:0] vec_id,

    output logic [31:0] inv_sqrt_out,
    output logic [id_width-1:0] id_out,
    output logic valid_out
);

    // -------------------------------------------------------------------------
    // Latency Parameters (CORRECT)
    // -------------------------------------------------------------------------
    localparam int CVT_L   = 6;
    localparam int ISQRT_L = 36;
    localparam int TOTAL_LATENCY = CVT_L + ISQRT_L; // 42

    // -------------------------------------------------------------------------
    // Input pipeline
    // -------------------------------------------------------------------------
    logic v_pipe;
    logic [id_width-1:0] id_pipe;
    logic [31:0] dot_sum_reg;

    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            v_pipe  <= 1'b0;
            id_pipe <= '0;
            dot_sum_reg <= '0;
        end else begin
            v_pipe  <= valid_in;
            id_pipe <= vec_id;
            dot_sum_reg <= dot_sum;
        end
    end

    // -------------------------------------------------------------------------
    // Fixed-to-Float Conversion
    // -------------------------------------------------------------------------
    logic [31:0] aa_fp;
    logic v_aa_conv;

    floating_point_1 cvt_aa (
        .aclk(clk),
        .s_axis_a_tvalid(v_pipe),
        .s_axis_a_tdata(dot_sum_reg),
        .m_axis_result_tvalid(v_aa_conv),
        .m_axis_result_tdata(aa_fp)
    );

    // -------------------------------------------------------------------------
    // inv_sqrt
    // -------------------------------------------------------------------------
    logic [31:0] inv_sqrt_aa;
    logic v_inv_a;

    inv_sqrt i_sqrt (
        .clk(clk),
        .nrst(nrst),
        .x_in(aa_fp),
        .valid_in(v_aa_conv),
        .y_out(inv_sqrt_aa),
        .valid_out(v_inv_a)
    );

    // -------------------------------------------------------------------------
    // Outputs (NO artificial delay)
    // -------------------------------------------------------------------------
    assign inv_sqrt_out = inv_sqrt_aa;
    assign valid_out    = v_inv_a;

    // ID alignment: exactly 42 cycles
    delay_pipe #(
        .WIDTH(id_width),
        .DEPTH(TOTAL_LATENCY)
    ) id_delay (
        .clk(clk),
        .nrst(nrst),
        .d(id_pipe),
        .q(id_out)
    );

endmodule
