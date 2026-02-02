module hbm_read #(
    parameter d_tensor_core = 32,
    parameter id_width = 32, 
    parameter num_ports = 32,
    parameter addr_width = 32,
    parameter data_width = 256
) (
    input  logic clk,
    input  logic nrst,
    input  logic start,
    output logic done,
    input  logic [addr_width-1:0] start_addr,
    input  logic [addr_width-1:0] end_addr,
    input  logic get_norm, 
    input  logic [10:0] d_model, 
    output logic [1023:0] db_vec [7:0], // 8 128 byte blocks
    output logic vec_valid,
    output logic [31:0] db_vec_norm [7:0],
    output logic [7:0] norm_valid,
    // output logic [id_width-1 :0] db_vec_id,


    // debugging
    // output logic [10:0] clk_cnt,
    // output logic [31:0] dot_prod_t [7:0],
    // output logic tc_vin,
    // output logic [7:0] tc_valid_t,
    // output logic [31:0] acc_t [7:0],
    // output logic [7:0] norm_t,
    // output logic [3:0] num_vectors_t [2:0],
    // output logic adder_valid_t,
    // AXI Master Ports
    output logic [num_ports-1:0][id_width-1:0]   m_axi_arid,
    output logic [num_ports-1:0][addr_width-1:0] m_axi_araddr,
    output logic [num_ports-1:0][7:0]            m_axi_arlen,
    output logic [num_ports-1:0][2:0]            m_axi_arsize,
    output logic [num_ports-1:0][1:0]            m_axi_arburst,
    output logic [num_ports-1:0]                 m_axi_arlock,
    output logic [num_ports-1:0][3:0]            m_axi_arcache,
    output logic [num_ports-1:0][3:0]            m_axi_arprot,
    output logic [num_ports-1:0][3:0]            m_axi_arqos,
    output logic [num_ports-1:0]                 m_axi_arvalid,
    input  logic [num_ports-1:0]                 m_axi_arready,
    input  logic [num_ports-1:0][id_width-1:0]   m_axi_rid,
    input  logic [num_ports-1:0][data_width-1:0] m_axi_rdata,
    input  logic [num_ports-1:0][1:0]            m_axi_rresp,
    input  logic [num_ports-1:0]                 m_axi_rlast,
    input  logic [num_ports-1:0]                 m_axi_rvalid,
    output logic [num_ports-1:0]                 m_axi_rready,
    
    // Write ports tied off
    output logic [num_ports-1:0][id_width-1:0]   m_axi_awid,
    output logic [num_ports-1:0][addr_width-1:0] m_axi_awaddr,
    output logic [num_ports-1:0][7:0]            m_axi_awlen,
    output logic [num_ports-1:0][2:0]            m_axi_awsize,
    output logic [num_ports-1:0][1:0]            m_axi_awburst,
    output logic [num_ports-1:0]                 m_axi_awvalid,
    input  logic [num_ports-1:0]                 m_axi_awready,
    output logic [num_ports-1:0][data_width-1:0] m_axi_wdata,
    output logic [num_ports-1:0][(data_width/8)-1:0] m_axi_wstrb,
    output logic [num_ports-1:0]                 m_axi_wlast,
    output logic [num_ports-1:0]                 m_axi_wvalid,
    input  logic [num_ports-1:0]                 m_axi_wready,
    input  logic [num_ports-1:0][id_width-1:0]   m_axi_bid,
    input  logic [num_ports-1:0][1:0]            m_axi_bresp,
    input  logic [num_ports-1:0]                 m_axi_bvalid,
    output logic [num_ports-1:0]                 m_axi_bready
);

    // --- FSM ---
    typedef enum logic [2:0] {ST_IDLE, ST_STREAM, ST_WAIT_TC, ST_DONE} state_t;
    state_t state;

    logic [3:0]group_size;
    logic trigger_ports;
    logic [num_ports-1:0] port_finished_mask;

    // --- 1. Control Logic & Config ---
    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            group_size       <= 4'd1;
            trigger_ports      <= 1'b0;
            port_finished_mask <= '0;
            state              <= ST_IDLE;
            done               <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        trigger_ports     <= 1'b1;
                        port_finished_mask <= '0;
                        state             <= ST_STREAM;
                        case (d_model)
                            11'd128:  begin group_size <= 4'd1; end
                            11'd256:  begin group_size <= 4'd2; end
                            11'd512:  begin group_size <= 4'd4; end
                            11'd1024: begin group_size <= 4'd8; end
                            11'd384:  begin group_size <= 4'd3; end
                            11'd768:  begin group_size <= 4'd6; end
                            default begin group_size <= 4'd1; end 
                        endcase
                    end
                end

                ST_STREAM: begin
                    if (&port_finished_mask) begin
                        trigger_ports <= 1'b0;
                        state         <= ST_WAIT_TC;
                    end
                    for (int p=0; p<num_ports; p++) begin
                        if (m_axi_rvalid[p] && m_axi_rlast[p] && m_axi_rready[p]) 
                            port_finished_mask[p] <= 1'b1;
                    end
                end

                ST_WAIT_TC: begin
                    if (valid_out) state <= ST_DONE;
                end

                ST_DONE: begin
                    done  <= 1'b1;
                    state <= ST_IDLE;
                end
            endcase
        end
    end

    // --- 2. Port Synchronization ---
    logic sync_data_valid;

    assign sync_data_valid = &m_axi_rvalid;
    assign m_axi_rready = {num_ports{sync_data_valid && (state == ST_STREAM)}};

    logic [data_width-1:0] port_data_raw [num_ports-1:0];
    logic [8191:0] combined_vector;

    genvar i;
    generate
        for (i = 0; i < num_ports; i++) begin : gen_ports
            hbm_port #(.BURST_LEN(256), .ID_WIDTH(id_width), .ADDR_WIDTH(addr_width), .DATA_WIDTH(data_width)) 
            hbm_port_inst (.clk(clk),.nrst(nrst),.start(trigger_ports),.done(),.valid_out(),.start_addr(start_addr),
            .end_addr(end_addr), .data_out(port_data_raw[i]),
            // Read Address
            .m_axi_arid(m_axi_arid[i]),
            .m_axi_araddr(m_axi_araddr[i]),
            .m_axi_arlen(m_axi_arlen[i]),
            .m_axi_arsize(m_axi_arsize[i]),
            .m_axi_arburst(m_axi_arburst[i]),
            .m_axi_arlock(m_axi_arlock[i]),
            .m_axi_arcache(m_axi_arcache[i]),
            .m_axi_arprot(m_axi_arprot[i]),
            .m_axi_arqos(m_axi_arqos[i]),
            .m_axi_arvalid(m_axi_arvalid[i]),
            .m_axi_arready(m_axi_arready[i]),
            // Read Data
            .m_axi_rid(m_axi_rid[i]),
            .m_axi_rdata(m_axi_rdata[i]),
            .m_axi_rresp(m_axi_rresp[i]),
            .m_axi_rlast(m_axi_rlast[i]),
            .m_axi_rvalid(m_axi_rvalid[i]),
            .m_axi_rready(m_axi_rready[i]),
            // Write Channel Tie-offs
            .m_axi_awid(m_axi_awid[i]),
            .m_axi_awaddr(m_axi_awaddr[i]),
            .m_axi_awlen(m_axi_awlen[i]),
            .m_axi_awsize(m_axi_awsize[i]),
            .m_axi_awburst(m_axi_awburst[i]),
            .m_axi_awvalid(m_axi_awvalid[i]),
            .m_axi_awready(m_axi_awready[i]),
            .m_axi_wdata(m_axi_wdata[i]),
            .m_axi_wstrb(m_axi_wstrb[i]),
            .m_axi_wlast(m_axi_wlast[i]),
            .m_axi_wvalid(m_axi_wvalid[i]),
            .m_axi_wready(m_axi_wready[i]),
            .m_axi_bid(m_axi_bid[i]),
            .m_axi_bresp(m_axi_bresp[i]),
            .m_axi_bvalid(m_axi_bvalid[i]),
            .m_axi_bready(m_axi_bready[i])
            );
            assign combined_vector[i*256 +: 256] = port_data_raw[i];
        end
    endgenerate

    assign db_vec = combined_vector;
    assign vec_valid = (sync_data_valid && (!get_norm));

    // --- 3. Tensor Core & Norm ---
    logic tc_valid_in;
    logic [1023:0] tc_vec_data [7:0];
    logic [id_width-1:0] tc_id_in [7:0]; 
    logic [31:0] tc_dot_prod [7:0];
    logic [id_width-1:0] tc_id_out [7:0];
    logic [7:0] tc_valid_out;
    logic [7:0] tc_vec_unpacked [7:0][127:0];
    logic [31:0] acc [7:0];
    logic [id_width-1:0] final_id;
    logic [7:0] norm_trigger;
    logic [id_width-1:0] norm_id_out; 
    logic [3:0] num_vectors [2:0];
    logic [7:0] norm_mask [2:0];
    logic [1:0] norm_ptr;
    logic [1023:0] fifo_din [7:0];
    logic [1023:0] fifo_dout [7:0];
    logic adder_valid_out;
    logic [1:0] vec_ptr;
    logic [7:0] n_valid;

    always_comb begin
        for (int i = 0; i < 8; i++) begin             
            for (int k = 0; k < 128; k++) begin       
                tc_vec_unpacked[i][k] = tc_vec_data[i][k*8 +: 8];
            end
        end
    end

    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            tc_valid_in <= '0;
            norm_trigger <= '0;
            tc_id_in <= '{default: '0};
            norm_ptr <= '0;
            vec_ptr <= '0;
        end else begin
            if (sync_data_valid) begin 
                tc_vec_data[0] <= combined_vector[1023:0];    
                tc_vec_data[1] <= combined_vector[2047:1024]; 
                tc_vec_data[2] <= combined_vector[3071:2048]; 
                tc_vec_data[3] <= combined_vector[4095:3072]; 
                tc_vec_data[4] <= combined_vector[5119:4096]; 
                tc_vec_data[5] <= combined_vector[6143:5120]; 
                tc_vec_data[6] <= combined_vector[7167:6144]; 
                tc_vec_data[7] <= combined_vector[8191:7168];

                tc_valid_in <= '1; 

            end else tc_valid_in <= '0;

            if (adder_valid_out) begin

                case (group_size)
                    4'd1: begin 
                        if (vec_ptr==0) begin norm_trigger <= 8'b11111111; num_vectors[0] <= 'd8; end 
                        if (vec_ptr==1) begin norm_trigger <= 8'b11111111; num_vectors[1] <= 'd8; end
                        if (vec_ptr==2) begin norm_trigger <= 8'b11111111; num_vectors[2] <= 'd8; end
                        end
                    4'd2: begin 
                        if (vec_ptr==0) begin norm_trigger <= 8'b00001111; num_vectors[0] <= 'd4; end
                        if (vec_ptr==1) begin norm_trigger <= 8'b00001111; num_vectors[1] <= 'd4; end
                        if (vec_ptr==2) begin norm_trigger <= 8'b00001111; num_vectors[2] <= 'd4; end
                        end
                    4'd4: begin 
                        if (vec_ptr==0) begin norm_trigger <= 8'b00000011; num_vectors[0] <= 'd2; end
                        if (vec_ptr==1) begin norm_trigger <= 8'b00000011; num_vectors[1] <= 'd2; end
                        if (vec_ptr==2) begin norm_trigger <= 8'b00000011; num_vectors[2] <= 'd2; end
                        end
                    4'd8: begin 
                        if (vec_ptr==0) begin norm_trigger <= 8'b00000001; num_vectors[0] <= 'd1; end
                        if (vec_ptr==1) begin norm_trigger <= 8'b00000001; num_vectors[1] <= 'd1; end
                        if (vec_ptr==2) begin norm_trigger <= 8'b00000001; num_vectors[2] <= 'd1; end
                        end
                    4'd3: begin 
                        if (vec_ptr==0) begin norm_trigger <= 8'b00000011; num_vectors[0] <= 'd2; end
                        if (vec_ptr==1) begin norm_trigger <= 8'b00000111; num_vectors[1] <= 'd3; end
                        if (vec_ptr==2) begin norm_trigger <= 8'b00000111; num_vectors[2] <= 'd3; end
                        end
                    4'd6: begin 
                        if (vec_ptr==0) begin norm_trigger <= 8'b00000001; num_vectors[0] <= 'd1; end
                        if (vec_ptr==1) begin norm_trigger <= 8'b00000001; num_vectors[1] <= 'd1; end
                        if (vec_ptr==2) begin norm_trigger <= 8'b00000011; num_vectors[2] <= 'd2; end
                        end              
                endcase
                if (vec_ptr<2)
                    vec_ptr <= vec_ptr + 1;
                else vec_ptr <= '0;
            end else begin norm_trigger <= '0; end
        end 

    end 


    adder_tree #(.ROOT_SIZE(8),.STAGES(3), .WIDTH(32))
    adder_inst(
    .clk(clk), .nrst(nrst),
    .group_size(group_size),
    .data(tc_dot_prod), 
    .valid_in(&tc_valid_out),
    .acc(acc), 
    .valid_out(adder_valid_out)
    );

    // latency = stages: 7
    genvar t;
    generate
        for (t = 0; t < 8; t++) begin : TCs
        tensor_core #(.id_width(id_width), .d_model(128), .stages(7))
        tc_inst (
            .clk(clk), .nrst(nrst), 
            .valid_in(tc_valid_in),
            .vec_a(tc_vec_unpacked[t]), .vec_b(tc_vec_unpacked[t]),
            .vec_id(tc_id_in[t]), 
            .dot_product(tc_dot_prod[t]),
            .id_out(tc_id_out[t]), .valid_out(tc_valid_out[t])
        );
        end
    endgenerate
    
    // latency = 42
    genvar n;
    generate
    for (n = 0; n < 8; n++) begin : norms
        norm #(.id_width(id_width)) norm_inst (
            .clk          (clk),
            .nrst         (nrst),
            .valid_in     (norm_trigger[n]),
            .dot_sum      (acc[n]), 
            .vec_id       (final_id[n]),   
            .inv_sqrt_out (db_vec_norm[n]),
            .id_out       (norm_id_out[n]),  
            .valid_out    (n_valid[n])   
        );
        end
    endgenerate

    always_comb begin
        if (get_norm)  norm_valid = n_valid; 
        else norm_valid = '0;
    end 

    // logic tc_vin;
    // assign dot_prod_t = tc_dot_prod;
    // assign tc_vin = tc_valid_in;
    // assign tc_valid_t = tc_valid_out;
    // assign acc_t = acc;
    // assign norm_t = norm_trigger;
    // assign num_vectors_t = num_vectors;
    // assign adder_valid_t = adder_valid_out;
endmodule