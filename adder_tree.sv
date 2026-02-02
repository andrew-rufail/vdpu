module adder_tree #(
    parameter ROOT_SIZE = 8,
    parameter STAGES    = 3, 
    parameter WIDTH     = 32
)(
    input  logic                        clk,
    input  logic                        nrst,
    input  logic [3:0]                  group_size,
    input  logic signed [WIDTH-1:0]     data [ROOT_SIZE-1:0], 
    input  logic                        valid_in,

    output logic signed [WIDTH-1:0]     acc [ROOT_SIZE-1:0], 
    output logic                        valid_out
);

    //-------------------------------------------------------------------------
    // Path A: Power of 2 (Standard Tree)
    //-------------------------------------------------------------------------
    logic signed [WIDTH-1:0] p2_s1 [3:0]; 
    logic signed [WIDTH-1:0] p2_s2 [1:0]; 
    logic signed [WIDTH-1:0] p2_s3;      

    // Latency Alignment Registers
    logic signed [WIDTH-1:0] p2_s1_pipe3 [3:0], p2_s1_pipe2 [3:0];
    logic signed [WIDTH-1:0] p2_s2_pipe3 [1:0];
    logic signed [WIDTH-1:0] data_pipe3 [ROOT_SIZE-1:0], data_pipe2 [ROOT_SIZE-1:0], data_pipe1 [ROOT_SIZE-1:0];

    always_ff @(posedge clk) begin
        if (valid_in) begin
            // Tree Logic
            p2_s1[0] <= data[0] + data[1];
            p2_s1[1] <= data[2] + data[3];
            p2_s1[2] <= data[4] + data[5];
            p2_s1[3] <= data[6] + data[7];
            
            p2_s2[0] <= p2_s1[0] + p2_s1[1];
            p2_s2[1] <= p2_s1[2] + p2_s1[3];
            
            p2_s3    <= p2_s2[0] + p2_s2[1];

            // Pipeline data to match 3-cycle latency
            data_pipe1 <= data;
            data_pipe2 <= data_pipe1;
            data_pipe3 <= data_pipe2;

            p2_s1_pipe2 <= p2_s1;
            p2_s1_pipe3 <= p2_s1_pipe2;

            p2_s2_pipe3 <= p2_s2;
        end
    end

    //-------------------------------------------------------------------------
    // Path B: 3 and 6 (Sliding Window Reduction)
    //-------------------------------------------------------------------------
    logic [1:0] phase_cnt;
    logic signed [WIDTH-1:0] hold [3:0];
    logic signed [WIDTH-1:0] path_b_sums [ROOT_SIZE-1:0];
    
    // Internal pipeline to bring Path B to 3-cycle latency
    logic signed [WIDTH-1:0] path_b_pipe1 [ROOT_SIZE-1:0];
    logic signed [WIDTH-1:0] path_b_pipe2 [ROOT_SIZE-1:0];
    logic signed [WIDTH-1:0] path_b_pipe3 [ROOT_SIZE-1:0];

    

    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            phase_cnt <= 2'd0;
            hold      <= '{default: 0};
            path_b_sums <= '{default: 0};
        end else if (valid_in) begin
            if (group_size == 3) begin
                case (phase_cnt)
                    2'd0: begin
                        path_b_sums[0] <= data[0] + data[1] + data[2];
                        path_b_sums[1] <= data[3] + data[4] + data[5];
                        path_b_sums[2] <= '0; 
                        hold[0]        <= data[6];
                        hold[1]        <= data[7];
                        phase_cnt      <= 2'd1;
                    end
                    2'd1: begin
                        path_b_sums[0] <= hold[0] + hold[1] + data[0];
                        path_b_sums[1] <= data[1] + data[2] + data[3];
                        path_b_sums[2] <= data[4] + data[5] + data[6];
                        hold[0]        <= data[7];
                        phase_cnt      <= 2'd2;
                    end
                    2'd2: begin
                        path_b_sums[0] <= hold[0] + data[0] + data[1];
                        path_b_sums[1] <= data[2] + data[3] + data[4];
                        path_b_sums[2] <= data[5] + data[6] + data[7];
                        hold           <= '{default: 0}; 
                        phase_cnt      <= 2'd0;
                    end
                endcase
            end else if (group_size == 6) begin
                case (phase_cnt)
                    2'd0: begin
                        path_b_sums[0] <= data[0] + data[1] + data[2] + data[3] + data[4] + data[5];
                        path_b_sums[1] <= '0;
                        hold[0]        <= data[6];
                        hold[1]        <= data[7];
                        phase_cnt      <= 2'd1;
                    end
                    2'd1: begin
                        path_b_sums[0] <= hold[0] + hold[1] + data[0] + data[1] + data[2] + data[3];
                        path_b_sums[1] <= '0;
                        hold[0]        <= data[4];
                        hold[1]        <= data[5];
                        hold[2]        <= data[6];
                        hold[3]        <= data[7];
                        phase_cnt      <= 2'd2;
                    end
                    2'd2: begin
                        path_b_sums[0] <= hold[0] + hold[1] + hold[2] + hold[3] + data[0] + data[1];
                        path_b_sums[1] <= data[2] + data[3] + data[4] + data[5] + data[6] + data[7];
                        hold <= '{default: 0}; 
                        phase_cnt      <= 2'd0;
                    end
                endcase
            end
        end
    end
    
    // Path B Latency Alignment
    always_ff @(posedge clk) begin
        path_b_pipe1 <= path_b_sums;
        path_b_pipe2 <= path_b_pipe1;
        path_b_pipe3 <= path_b_pipe2;
    end

    //-------------------------------------------------------------------------
    // Control Pipeline
    //-------------------------------------------------------------------------
    logic [3:0] group_size_pipe [STAGES:0];
    logic v_pipe [STAGES:0];

    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            v_pipe <= '{default: 0};
        end else begin
            v_pipe[0]          <= valid_in;
            group_size_pipe[0] <= group_size;
            for (int i = 1; i <= STAGES; i++) begin
                v_pipe[i]          <= v_pipe[i-1];
                group_size_pipe[i] <= group_size_pipe[i-1];
            end
        end
    end

    //-------------------------------------------------------------------------
    // Output MUX
    //-------------------------------------------------------------------------
    always_comb begin
        acc       = '{default: '0};
        valid_out = v_pipe[STAGES];
        
        if (group_size_pipe[STAGES] == 3 || group_size_pipe[STAGES] == 6) begin
            acc = path_b_pipe3; 
        end else begin
            case (group_size_pipe[STAGES])
                4'd1: acc[0] = p2_s3;
                4'd2: begin 
                    acc[0] = p2_s1_pipe3[0]; 
                    acc[1] = p2_s1_pipe3[1]; 
                    acc[2] = p2_s1_pipe3[2]; 
                    acc[3] = p2_s1_pipe3[3]; 
                end
                4'd4: begin 
                    acc[0] = p2_s2_pipe3[0]; 
                    acc[1] = p2_s2_pipe3[1];
                    
                end
                4'd8: begin
                    acc = data_pipe3;
                end
                default: acc[0] = p2_s3;
            endcase
        end
    end

endmodule