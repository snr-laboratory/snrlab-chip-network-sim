module chip_fifo_router #(
    parameter int WIDTH = 64,
    parameter int DEPTH = 1024
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic [15:0]      cfg_fifo_depth,
    input  logic             local_valid,
    input  logic [WIDTH-1:0] local_data,
    input  logic             neigh_valid,
    input  logic [WIDTH-1:0] neigh_data,
    input  logic             out_ready,
    output logic             out_valid,
    output logic [WIDTH-1:0] out_data,
    output logic             drop_local,
    output logic             drop_neigh,
    output logic [15:0]      occupancy
);

    localparam int PTR_W = $clog2(DEPTH);

    logic [WIDTH-1:0] mem [0:DEPTH-1];
    logic [PTR_W-1:0] rd_ptr;
    logic [PTR_W-1:0] wr_ptr;
    logic [15:0]      count;

    function automatic [15:0] effective_depth(input [15:0] req);
        if (req == 0) begin
            effective_depth = 16'd1;
        end else if (req > DEPTH[15:0]) begin
            effective_depth = DEPTH[15:0];
        end else begin
            effective_depth = req;
        end
    endfunction

    assign out_valid = (count != 0);
    assign out_data  = mem[rd_ptr];
    assign occupancy = count;

    always_ff @(posedge clk) begin
        logic [15:0]      cap;
        logic [15:0]      avail;
        logic [15:0]      next_count;
        logic [PTR_W-1:0] next_rd;
        logic [PTR_W-1:0] next_wr;
        logic             pop_fire;

        if (!rst_n) begin
            rd_ptr      <= '0;
            wr_ptr      <= '0;
            count       <= '0;
            drop_local  <= 1'b0;
            drop_neigh  <= 1'b0;
        end else begin
            cap       = effective_depth(cfg_fifo_depth);
            pop_fire  = (out_ready && (count != 0));
            next_rd   = rd_ptr;
            next_wr   = wr_ptr;
            next_count = count;
            drop_local <= 1'b0;
            drop_neigh <= 1'b0;

            if (pop_fire) begin
                next_rd    = rd_ptr + 1'b1;
                next_count = next_count - 1'b1;
            end

            avail = cap - next_count;

            // Local data has strict priority when both are valid.
            if (local_valid) begin
                if (avail != 0) begin
                    mem[next_wr] = local_data;
                    next_wr      = next_wr + 1'b1;
                    next_count   = next_count + 1'b1;
                    avail        = avail - 1'b1;
                end else begin
                    drop_local <= 1'b1;
                end
            end

            if (neigh_valid) begin
                if (avail != 0) begin
                    mem[next_wr] = neigh_data;
                    next_wr      = next_wr + 1'b1;
                    next_count   = next_count + 1'b1;
                    avail        = avail - 1'b1;
                end else begin
                    drop_neigh <= 1'b1;
                end
            end

            rd_ptr <= next_rd;
            wr_ptr <= next_wr;
            count  <= next_count;
        end
    end

endmodule
