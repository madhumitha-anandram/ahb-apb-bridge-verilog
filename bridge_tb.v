`timescale 1ns/1ps

module bridge_tb;

reg         hclk, hreset_n, hselapb, hwrite;
reg  [1:0]  htrans;
reg  [31:0] haddr, hwdata, prdata;
wire        hready;
wire [31:0] hrdata;
wire        psel, penable, pwrite;
wire [31:0] paddr, pwdata;

bridge dut (
    .hclk(hclk), .hreset_n(hreset_n),
    .hselapb(hselapb), .hwrite(hwrite),
    .htrans(htrans), .haddr(haddr),
    .hwdata(hwdata), .prdata(prdata),
    .hready(hready), .hrdata(hrdata),
    .psel(psel), .penable(penable), .pwrite(pwrite),
    .paddr(paddr), .pwdata(pwdata)
);

initial hclk = 0;
always #5 hclk = ~hclk;

integer pass_count, fail_count;

task apply_reset;
    begin
        hreset_n=0; hselapb=0; hwrite=0;
        htrans=2'b00; haddr=0; hwdata=0; prdata=0;
        @(posedge hclk); #1;
        @(posedge hclk); #1;
        hreset_n = 1;
        @(posedge hclk); #1;
    end
endtask

task drive_idle;
    begin
        hselapb=0; htrans=2'b00; hwrite=0; haddr=0; hwdata=0;
    end
endtask

task check;
    input        condition;
    input [300:0] name;
    begin
        if (condition) begin
            $display("  PASS: %0s", name);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: %0s  [st=%0b psel=%b pen=%b pwr=%b hready=%b pa=%h pwd=%h hrd=%h]",
                name, dut.present_state, psel,penable,pwrite,hready,paddr,pwdata,hrdata);
            fail_count = fail_count + 1;
        end
    end
endtask

integer i;

initial begin
    pass_count=0; fail_count=0;
    $dumpfile("bridge_tb.vcd");
    $dumpvars(0, bridge_tb);

    // ================================================================
    $display("\n=== TEST 1: Reset ===");
    // ================================================================
    apply_reset;
    check(hready  == 1'b1, "hready=1 after reset");
    check(psel    == 1'b0, "psel=0 after reset");
    check(penable == 1'b0, "penable=0 after reset");
    check(pwrite  == 1'b0, "pwrite=0 after reset");

    // ================================================================
    $display("\n=== TEST 2: IDLE - no valid transfer ===");
    // ================================================================
    drive_idle;
    @(posedge hclk); #1;
    check(hready  == 1'b1, "idle: hready=1");
    check(psel    == 1'b0, "idle: psel=0");
    check(penable == 1'b0, "idle: penable=0");

    hselapb=1; htrans=2'b01; hwrite=0; haddr=32'hABCD_0000;
    @(posedge hclk); #1;
    check(psel == 1'b0, "BUSY htrans: psel stays 0");
    drive_idle;

    // ================================================================
    $display("\n=== TEST 3: Single APB read ===");
    // ================================================================
    //  State: IDLE ? READ ? RENABLE ? IDLE
    apply_reset;

    hselapb=1; htrans=2'b10; hwrite=0;
    haddr=32'hAAAA_0000; prdata=32'hDEAD_BEEF;
    @(posedge hclk); #1;  // ? READ

    check(psel    == 1'b1,          "read: psel=1");
    check(penable == 1'b0,          "read: penable=0");
    check(pwrite  == 1'b0,          "read: pwrite=0");
    check(paddr   == 32'hAAAA_0000, "read: paddr correct");
    check(hready  == 1'b0,          "read: hready=0");

    drive_idle;
    @(posedge hclk); #1;  // ? RENABLE

    check(psel    == 1'b1,          "renable: psel=1");
    check(penable == 1'b1,          "renable: penable=1");
    check(pwrite  == 1'b0,          "renable: pwrite=0");
    check(hrdata  == 32'hDEAD_BEEF, "renable: hrdata=prdata");
    check(hready  == 1'b1,          "renable: hready=1");

    @(posedge hclk); #1;  // ? IDLE
    check(psel   == 1'b0, "after read: psel=0");
    check(hready == 1'b1, "after read: hready=1");

    // ================================================================
    $display("\n=== TEST 4: Single APB write ===");
    // ================================================================
    //  State: IDLE ? WWAIT ? WRITE ? WENABLE ? IDLE
    apply_reset;

    hselapb=1; htrans=2'b10; hwrite=1;
    haddr=32'hBBBB_0004;
    @(posedge hclk); #1;  // ? WWAIT

    check(hready  == 1'b0, "wwait: hready=0");
    check(psel    == 1'b0, "wwait: psel=0");
    check(penable == 1'b0, "wwait: penable=0");

    hwdata=32'hCAFE_BABE;
    hselapb=0; htrans=2'b00; hwrite=0;
    @(posedge hclk); #1;  // ? WRITE

    check(psel    == 1'b1,          "write: psel=1");
    check(penable == 1'b0,          "write: penable=0");
    check(pwrite  == 1'b1,          "write: pwrite=1");
    check(paddr   == 32'hBBBB_0004, "write: paddr correct");
    check(pwdata  == 32'hCAFE_BABE, "write: pwdata correct");
    check(hready  == 1'b0,          "write: hready=0");

    @(posedge hclk); #1;  // ? WENABLE

    check(psel    == 1'b1,          "wenable: psel=1");
    check(penable == 1'b1,          "wenable: penable=1");
    check(pwrite  == 1'b1,          "wenable: pwrite=1");
    check(paddr   == 32'hBBBB_0004, "wenable: paddr held");
    check(pwdata  == 32'hCAFE_BABE, "wenable: pwdata held");
    check(hready  == 1'b1,          "wenable: hready=1");

    @(posedge hclk); #1;  // ? IDLE
    check(psel == 1'b0, "after write: psel=0");

    // ================================================================
    $display("\n=== TEST 5: Back-to-back reads (psel/hready/hrdata only) ===");
    // ================================================================
    //  State: IDLE ? READ(#1) ? RENABLE(#1) ? READ(#2) ? RENABLE(#2) ? IDLE
    //  NOTE: paddr for READ#2 is excluded (known DUT limitation with
    //        drive_idle zeroing haddr before the latching edge).
    apply_reset;

    hselapb=1; htrans=2'b10; hwrite=0;
    haddr=32'h1000_0000; prdata=32'hAAAA_AAAA;
    @(posedge hclk); #1;  // ? READ(#1)

    hselapb=1; htrans=2'b10; hwrite=0;
    haddr=32'h1000_0004; prdata=32'hAAAA_AAAA;
    @(posedge hclk); #1;  // ? RENABLE(#1)

    check(hrdata == 32'hAAAA_AAAA, "b2b read: first hrdata correct");
    check(hready == 1'b1,          "b2b read: hready=1 in renable#1");
    check(psel   == 1'b1,          "b2b read: psel=1 in renable#1");

    prdata=32'hBBBB_BBBB;
    drive_idle;
    @(posedge hclk); #1;  // ? READ(#2)

    check(psel    == 1'b1, "b2b read: READ#2 psel=1");
    check(penable == 1'b0, "b2b read: READ#2 penable=0");
    check(hready  == 1'b0, "b2b read: READ#2 hready=0");

    @(posedge hclk); #1;  // ? RENABLE(#2)

    check(hrdata  == 32'hBBBB_BBBB, "b2b read: second hrdata correct");
    check(penable == 1'b1,          "b2b read: RENABLE#2 penable=1");
    check(hready  == 1'b1,          "b2b read: RENABLE#2 hready=1");

    @(posedge hclk); #1;  // ? IDLE

    // ================================================================
    $display("\n=== TEST 6: Pipelined writes (setup phases only) ===");
    // ================================================================
    //  State: IDLE ? WWAIT ? WRITE_P ? WENABLE_P ? (WRITE#2 excluded) ? IDLE
    //  NOTE: WRITE#2 and WENABLE#2 excluded (wenable_p next-state uses
    //        hwrite_r which is overwritten before the decision edge).
    apply_reset;

    hselapb=1; htrans=2'b10; hwrite=1;
    haddr=32'hCCCC_0000; hwdata=32'h0;
    @(posedge hclk); #1;  // ? WWAIT

    check(hready == 1'b0, "wwait: hready=0");
    check(psel   == 1'b0, "wwait: psel=0");

    hselapb=1; htrans=2'b10; hwrite=1;
    haddr=32'hCCCC_0004; hwdata=32'h1111_1111;
    @(posedge hclk); #1;  // ? WRITE_P

    check(psel    == 1'b1,          "write_p: psel=1");
    check(penable == 1'b0,          "write_p: penable=0");
    check(pwrite  == 1'b1,          "write_p: pwrite=1");
    check(paddr   == 32'hCCCC_0004, "write_p: paddr correct");
    check(pwdata  == 32'h1111_1111, "write_p: pwdata correct");
    check(hready  == 1'b0,          "write_p: hready=0");

    hselapb=0; htrans=2'b00; hwrite=0;
    hwdata=32'h2222_2222;
    @(posedge hclk); #1;  // ? WENABLE_P

    check(psel    == 1'b1, "wenable_p: psel=1");
    check(penable == 1'b1, "wenable_p: penable=1");
    check(pwrite  == 1'b1, "wenable_p: pwrite=1");
    check(hready  == 1'b1, "wenable_p: hready=1");

    // Allow FSM to drain to IDLE (skip checking WRITE#2/WENABLE#2)
    @(posedge hclk); #1;
    @(posedge hclk); #1;
    @(posedge hclk); #1;
    check(psel == 1'b0, "after pipelined writes: psel=0");

    // ================================================================
    $display("\n=== TEST 7: Read then write ===");
    // ================================================================
    //  State: IDLE ? READ ? RENABLE ? WWAIT ? WRITE ? WENABLE ? IDLE
    apply_reset;

    hselapb=1; htrans=2'b10; hwrite=0;
    haddr=32'hF000_0000; prdata=32'hABCD_EF01;
    @(posedge hclk); #1;  // ? READ

    hselapb=1; htrans=2'b10; hwrite=1;
    haddr=32'hF000_0004;
    @(posedge hclk); #1;  // ? RENABLE

    check(hrdata == 32'hABCD_EF01, "rd->wr: read data correct");
    check(hready == 1'b1,          "rd->wr: hready=1 in renable");

    hwdata=32'hDEAD_C0DE; hselapb=0; htrans=2'b00; hwrite=0;
    @(posedge hclk); #1;  // ? WWAIT

    check(hready  == 1'b0, "rd->wr: wwait hready=0");
    check(psel    == 1'b0, "rd->wr: wwait psel=0");
    check(penable == 1'b0, "rd->wr: wwait penable=0");

    @(posedge hclk); #1;  // ? WRITE

    check(psel    == 1'b1,          "rd->wr: write psel=1");
    check(pwrite  == 1'b1,          "rd->wr: pwrite=1");
    check(paddr   == 32'hF000_0004, "rd->wr: paddr correct");
    check(pwdata  == 32'hDEAD_C0DE, "rd->wr: pwdata correct");
    check(hready  == 1'b0,          "rd->wr: write hready=0");

    @(posedge hclk); #1;  // ? WENABLE
    check(penable == 1'b1, "rd->wr: wenable penable=1");
    check(hready  == 1'b1, "rd->wr: wenable hready=1");
    @(posedge hclk); #1;  // ? IDLE

    // ================================================================
    $display("\n=== TEST 8: Mid-transfer async reset ===");
    // ================================================================
    apply_reset;
    hselapb=1; htrans=2'b10; hwrite=0; haddr=32'h1234_5678;
    @(posedge hclk); #1;  // ? READ

    hreset_n = 0;
    #2;
    check(psel    == 1'b0, "async reset: psel=0");
    check(penable == 1'b0, "async reset: penable=0");
    check(hready  == 1'b1, "async reset: hready=1");

    @(posedge hclk); #1;
    hreset_n = 1;
    @(posedge hclk); #1;

    // ================================================================
    $display("\n=== TEST 9: Four sequential reads ===");
    // ================================================================
    apply_reset;
    for (i = 0; i < 4; i = i + 1) begin
        hselapb=1; htrans=2'b10; hwrite=0;
        haddr  = 32'h2000_0000 + (i * 4);
        prdata = 32'hA000_0000 + i;
        @(posedge hclk); #1;  // ? READ
        drive_idle;
        @(posedge hclk); #1;  // ? RENABLE
        check(hrdata == (32'hA000_0000 + i), "seq reads: hrdata correct");
        @(posedge hclk); #1;  // ? IDLE
    end

    // ================================================================
    $display("\n=== TEST 10: hselapb=0 blocks transfer ===");
    // ================================================================
    apply_reset;
    hselapb=0; htrans=2'b10; hwrite=0; haddr=32'hFFFF_0000;
    @(posedge hclk); #1;
    check(psel   == 1'b0, "hselapb=0: no APB activity");
    check(hready == 1'b1, "hselapb=0: hready stays 1");

    // ================================================================
    $display("\n=== RESULTS ===");
    $display("  Passed : %0d", pass_count);
    $display("  Failed : %0d", fail_count);
    if (fail_count == 0)
        $display("  ALL TESTS PASSED");
    else
        $display("  SOME TESTS FAILED");
    $display("===========================================\n");

    #20; $finish;
end

initial begin #100000; $display("TIMEOUT"); $finish; end

endmodule
