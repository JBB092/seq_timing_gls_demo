// Compares the captured chain output with the reference and counts errors
module error_checker #(
    parameter int COUNT_WIDTH = 24
) (
    input  logic                   clk,
    input  logic                   clr,        // synchronous, active high
    input  logic                   chain_bit,
    input  logic                   ref_bit,
    output logic [COUNT_WIDTH-1:0] err_count,  // saturates at all ones
    output logic                   err_flag    // sticky until clr
);

    logic mismatch;
    assign mismatch = chain_bit != ref_bit;

    always_ff @(posedge clk) begin
        if (clr) begin
            err_count <= '0;
            err_flag  <= 1'b0;
        end else if (mismatch) begin
            err_flag <= 1'b1;
            if (err_count != '1)
                err_count <= err_count + 1'b1;
        end
    end

endmodule
