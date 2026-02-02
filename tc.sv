module tensor_core#(
    parameter id_width = 20, 
    parameter d_model  = 64, 
    parameter stages   =  6
)(
    input  logic clk,
    input  logic nrst,
    input  logic valid_in,
    input  logic [7:0] vec_a[d_model-1:0],
    input  logic [7:0] vec_b[d_model-1:0],
    input  logic [id_width-1:0] vec_id,

    output logic signed [31:0] dot_product,
    output logic [id_width-1:0] id_out,
    output logic valid_out
);

    // -------------------------------------------------------------------------
    // Input Processing
    // -------------------------------------------------------------------------
    logic signed [15:0] ab_prod_array [d_model-1:0];

    logic [id_width-1:0] id_pipe [stages+1:0];
    logic v_pipe [stages+1:0];

    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            v_pipe[0]  <= 1'b0;
            id_pipe[0] <= '0;
        end else begin
            v_pipe[0]  <= valid_in;
            id_pipe[0] <= vec_id;
            for (int i = 0; i < d_model; i++) begin
                ab_prod_array[i] <= signed'(vec_a[i]) * signed'(vec_b[i]);
            end
        end
    end

    // -------------------------------------------------------------------------
    // Adder Tree Storage
    // -------------------------------------------------------------------------
    generate
        for (genvar s = 0; s <= stages; s++) begin : tree_storage
            localparam int STAGE_BIT_WIDTH = 16 + s;
            logic signed [STAGE_BIT_WIDTH-1:0] sum_ab [d_model >> s];
        end
    endgenerate

    assign tree_storage[0].sum_ab = ab_prod_array;

    generate
        for (genvar s = 0; s < stages; s++) begin : stage_gen
            always_ff @(posedge clk or negedge nrst) begin
                if (!nrst) begin
                    v_pipe[s+1]  <= 1'b0;
                    id_pipe[s+1] <= '0;
                end else begin
                    v_pipe[s+1]  <= v_pipe[s];
                    id_pipe[s+1] <= id_pipe[s];
                    for (int i = 0; i < (d_model >> (s+1)); i++) begin
                        tree_storage[s+1].sum_ab[i] <=
                            tree_storage[s].sum_ab[2*i] +
                            tree_storage[s].sum_ab[2*i+1];
                    end
                end
            end
        end
    endgenerate

    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            v_pipe[stages+1]  <= 1'b0;
            id_pipe[stages+1] <= '0;
        end else begin
            v_pipe[stages+1]  <= v_pipe[stages];
            id_pipe[stages+1] <= id_pipe[stages];
        end
    end
    // -------------------------------------------------------------------------
    // Final Output (Exact Dot Product)
    // -------------------------------------------------------------------------
    assign dot_product = 32'(tree_storage[stages].sum_ab[0]);
    assign valid_out   = v_pipe[stages+1];
    assign id_out      = id_pipe[stages+1];

endmodule
