module cache_dut_tb;
    //---------------------------------------------------------------------------------
    // Time unit setup.
    //---------------------------------------------------------------------------------
    timeunit 1ps;
    timeprecision 1ps;
    int timeout = 100;

    //---------------------------------------------------------------------------------
    // Waveform generation.
    //---------------------------------------------------------------------------------
    initial begin
        $fsdbDumpfile("dump.fsdb");
        $fsdbDumpvars(0, cache_dut_tb, "+all");
        $display("Dump successful (haha dump)");
        reset();
    end

    //---------------------------------------------------------------------------------
    // TODO: Declare cache port signals:
    //---------------------------------------------------------------------------------

    //---------------------------------------------------------------------------------
    // TODO: Generate a clock:
    //---------------------------------------------------------------------------------
    bit clk;
    initial clk = 1'b1;
    always #5 clk = clk === 1'b0;
    always @(posedge clk) begin
        if(timeout == 0) begin
            $display("Testbench timed out");
            $finish;
        end
        timeout <= timeout - 1;
    end
    //---------------------------------------------------------------------------------
    // TODO: Write a task to generate reset:
    //---------------------------------------------------------------------------------
    bit rst;
    // cpu side signals, ufp -> upward facing port
    logic   [31:0]  ufp_addr;
    logic   [3:0]   ufp_rmask;
    logic   [3:0]   ufp_wmask;
    logic   [31:0]  ufp_rdata;
    logic   [31:0]  ufp_wdata;
    logic           ufp_resp;
    // memory side signals, dfp -> downward facing port
    logic   [31:0]  dfp_addr;
    logic           dfp_read;
    logic           dfp_write;
    logic   [255:0] dfp_rdata;
    logic   [255:0] dfp_wdata;
    logic           dfp_resp;
    //extras
    logic cache_resp;
    logic [63:0] cache_rdata;
    logic cache_read;
    logic cache_write;
    logic [31:0] cache_address;
    logic [63:0] cache_wdata;
    task reset;
        rst = 1'b1;
        repeat (2) @(posedge clk);
        rst <= 1'b0;
    endtask
    //---------------------------------------------------------------------------------
    // TODO: Instantiate the DUT and physical memory:
    //---------------------------------------------------------------------------------
    mem_itf mem_itf(.*);
    simple_memory mem(.itf(mem_itf));
    cache dut(
        .clk          (clk),
        .rst          (rst),
        .ufp_addr (ufp_addr),
        .ufp_rmask    (ufp_rmask),
        .ufp_wmask   (ufp_wmask),
        .ufp_rdata   (ufp_rdata),        
        .ufp_wdata   (ufp_wdata),
        .ufp_resp    (ufp_resp),

        .dfp_addr(mem_itf.addr),
        .dfp_read(mem_itf.read),
        .dfp_write(mem_itf.write),
        .dfp_rdata(mem_itf.rdata),
        .dfp_wdata(mem_itf.wdata),
        .dfp_resp(mem_itf.resp)
    );

    //---------------------------------------------------------------------------------
    // TODO: Write tasks to test various functionalities:
    //---------------------------------------------------------------------------------

    task do_read_hit;
    //Fill all cache lines
        static logic[4:0] offset;
        static logic[2:0] index;
        static logic[23:0] tag;

        for(int i = 0; i < 8; i++) begin
            offset = 5'b00000;
            index = i[2:0];
            tag = (2*i);
            ufp_addr <= {tag, index, offset};
            ufp_rmask <= 4'b1111;
            repeat (2) @(posedge clk);

            offset = 5'b00000;
            index = i[2:0];
            tag = (2*i) + 1;
            ufp_addr <= {tag, index, offset};
            ufp_rmask <= 4'b1110;
            repeat (2) @(posedge clk);

            offset = 5'b00000;
            index = i[2:0];
            tag = (2*i) + 2;
            ufp_addr <= {tag, index, offset};
            ufp_rmask <= 4'b1101;
            repeat (2) @(posedge clk);

            offset = 5'b00000;
            index = i[2:0];
            tag = (2*i) + 3;
            ufp_addr <= {tag, index, offset};
            ufp_rmask <= 4'b1100;
            repeat (2) @(posedge clk);

            assert (ufp_resp === 1'b1);
            assert (mem_itf.write === 1'b0);
            assert (mem_itf.read === 1'b0);
            @(posedge clk);
            assert(ufp_resp === 1'b0);
            assert(mem_itf.write === 1'b0);
            assert(mem_itf.read === 1'b0);
        end
    endtask

    //---------------------------------------------------------------------------------
    // TODO: Main initial block that calls your tasks, then calls $finish
    //---------------------------------------------------------------------------------
    always @(posedge clk) begin
        do_read_hit();
        if (timeout == 0) begin
            $error("TB Error: Timed out");
            $finish;
        end
        if (mem_itf.error != 0) begin
            repeat (5) @(posedge clk);
            $finish;
        end
        timeout <= timeout - 1;
    end
endmodule : cache_dut_tb
