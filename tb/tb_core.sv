`include "chain_cfg.svh"

// Self-checking testbench for core: sweeps the clock period T for the
// compiled CHAIN_DEPTH and prints a T -> PASS/FAIL table
// Plusargs (all in ps): +T_MAX=40000 +T_MIN=2000 +T_STEP=2000 +CYCLES=1000
module tb_core;

    timeunit 1ps;
    timeprecision 1ps;

    localparam int              WIDTH       = 16;
    localparam int              DEPTH       = `CHAIN_DEPTH;
    localparam logic [WIDTH-1:0] TAPS        = 16'hB400;  // same as lfsr.sv
    localparam logic [WIDTH-1:0] SEED        = 16'hACE1;
    localparam int              RST_CYCLES  = 3;          // core needs at least 2
    localparam int              MAX_POINTS  = 256;

    // DUT
    logic        clk = 1'b0;
    logic        rst = 1'b1;
    logic        clr = 1'b0;
    logic        chain_q;
    logic        ref_q;
    logic [23:0] err_count;
    logic        err_flag;

    core u_dut (
        .clk       (clk),
        .rst       (rst),
        .clr       (clr),
        .chain_q   (chain_q),
        .ref_q     (ref_q),
        .err_count (err_count),
        .err_flag  (err_flag)
    );

    // Clock with a period that the sweep can change
    int unsigned period = 40000;

    initial forever begin
        #(period / 2)          clk = 1'b1;
        #(period - period / 2) clk = 1'b0;
    end

    // Own model of the LFSR and the chain, so it doesn't depend on DUT internals
    logic [WIDTH-1:0] m_lfsr;
    logic             expected;
    logic             check_en = 1'b0;

    function automatic logic chain_func(logic [WIDTH-1:0] din);
        logic y = din[0];
        for (int i = 1; i <= DEPTH; i++)
            y = y ^ din[1 + (i-1) % (WIDTH-1)];
        return y;
    endfunction

    // Model steps on the same edge as the DUT; rst only changes on the
    // falling edge, so reading it here is race free
    always @(posedge clk) begin
        expected = chain_func(m_lfsr);
        check_en = !rst;  // the value captured on this edge is valid
        m_lfsr   = rst ? SEED : {m_lfsr[WIDTH-2:0], ^(m_lfsr & TAPS)};
    end

    // Outputs are checked half a period after the edge that captured them;
    // !== makes an X count as an error
    int unsigned chain_err;
    int unsigned ref_err;
    int unsigned x_count;

    always @(negedge clk) begin
        if (check_en) begin
            if (chain_q !== expected) chain_err++;
            if (ref_q   !== expected) ref_err++;
            if ($isunknown({chain_q, ref_q})) x_count++;
        end
    end

    // Sweep
    int t_max  = 40000;
    int t_min  = 2000;
    int t_step = 2000;
    int cycles = 1000;

    int unsigned res_t     [MAX_POINTS];
    int unsigned res_chain [MAX_POINTS];
    int unsigned res_ref   [MAX_POINTS];
    int unsigned res_x     [MAX_POINTS];
    int          n_points  = 0;
    int          n_fail    = 0;

    task automatic run_point(int t);
        // Change the period and reset while the clock is low
        @(negedge clk);
        period = t;
        rst    = 1'b1;
        repeat (RST_CYCLES) @(negedge clk);
        rst = 1'b0;
        chain_err = 0;
        ref_err   = 0;
        x_count   = 0;
        repeat (cycles) @(negedge clk);
        @(posedge clk);  // let the last check finish before reading the counters

        res_t[n_points]     = t;
        res_chain[n_points] = chain_err;
        res_ref[n_points]   = ref_err;
        res_x[n_points]     = x_count;
        if (chain_err != 0 || ref_err != 0) n_fail++;
        n_points++;
    endtask

    initial begin
        void'($value$plusargs("T_MAX=%d",  t_max));
        void'($value$plusargs("T_MIN=%d",  t_min));
        void'($value$plusargs("T_STEP=%d", t_step));
        void'($value$plusargs("CYCLES=%d", cycles));
        m_lfsr = SEED;

        if (t_step <= 0) $fatal(1, "T_STEP must be positive");
        for (int t = t_max; t >= t_min && n_points < MAX_POINTS; t -= t_step)
            run_point(t);

        $display("");
        $display("==== T sweep: CHAIN_DEPTH=%0d, %0d cycles per T ====", DEPTH, cycles);
        $display("%8s %10s %10s %8s  %s", "T(ps)", "chain_err", "ref_err", "x_count", "result");
        for (int i = 0; i < n_points; i++)
            $display("%8d %10d %10d %8d  %s", res_t[i], res_chain[i], res_ref[i], res_x[i],
                     (res_chain[i] == 0 && res_ref[i] == 0) ? "PASS" : "FAIL");
        $display("==== %0d of %0d periods failed ====", n_fail, n_points);
        $display("");

        if (n_fail != 0)
            $fatal(1, "CHAIN_DEPTH=%0d failed at %0d of %0d periods", DEPTH, n_fail, n_points);
        $finish;
    end

endmodule
