module inv_norm(
    input logic clk,
    input logic nrst,
    input logic valid_in,
    input logic [31:0] d_in,
    output logic signed [31:0] d_out,
    output logic [5:0] scale,
    output logic valid_out
);
    //------------------------------------------
    //Computes 1/||A|| using fixed point logic
    //------------------------------------------

    //Shift d_in to leading one val
    logic [5:0] scale_pipe [2:0];
    logic [1:0] v_pipe;
    logic [4:0] leading_zeros; 
    logic [31:0] val;
    always_comb begin
        leading_zeros = 0;
        for (int i=31; i>=0; i--) begin
            if (d_in[i]) break;
            else leading_zeros++;
        end 
        if (d_in==0) val=0;
        else val = d_in << leading_zeros;
        scale_pipe[0] = leading_zeros;
    end

    //LUT for 1/sqrt(x)
    logic [6:0] lut_addr;
    logic  [15:0] lut_m, lut_b, b_final; //Q15
    logic  [15:0] frac_bits_d1;
    logic signed [31:0] mult_res;

    assign lut_addr = val[30:24];
    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin frac_bits_d1 <= '0; v_pipe[0] = '0; scale_pipe[0] <= '0; end
        else frac_bits_d1 <= val[23:8];
        v_pipe[0] <= (valid_in);
        scale_pipe[1] <= scale_pipe[0];
    end 

    inv_sqrt_lut lookup (
        .clk(clk),
        .addr(lut_addr),
        .slope(lut_m),
        .base(lut_b)
    );

    // y=mx+b
    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin mult_res <=0; v_pipe[1] = '0; scale_pipe[1] <= '0; end
        else begin  
            mult_res <= (signed'(lut_m) * signed'({1'b0, frac_bits_d1})) >>> 16;
            b_final  <= lut_b;
            scale_pipe[2] <= scale_pipe[1];
            v_pipe[1] <= v_pipe[0];
        end
    end 

    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin d_out<=0; valid_out <=0; end
        else begin  
            d_out <= signed'(mult_res) + signed'({16'b0, b_final});
            scale <= scale_pipe[2];
            valid_out <= v_pipe[1];  
        end
    end 
    


endmodule