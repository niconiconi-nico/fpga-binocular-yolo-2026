`timescale 1ns/1ps
module tb_ingress1;
    localparam N=16*8;
    reg clk=0,pclk=0,rst=1;
    always #4 clk=~clk;
    always #6.666 pclk=~pclk;
    reg gv=0,ge=0;reg [7:0] gd=0;
    reg ready=1,drained=0,boundary=0;
    wire mv,fv,available;wire [1:0] mb,fb;   // CLAUDE Z29B: up to three bankswire [31:0] ma,fid,cc,bn,bv;wire [15:0] md;
    reg [15:0] memory[0:3*N-1];
    integer writes=0,checks=0;
    remote_media_ingress5 #(.WIDTH(16),.HEIGHT(8)) dut(.rx_clk(clk),.pixel_clk(pclk),.rst(rst),
        .gmii_valid(gv),.gmii_error(ge),.gmii_data(gd),
        .mem_valid(mv),.mem_bank(mb),.mem_ready(ready),.mem_drained(drained),
        .mem_pixel_addr(ma),.mem_pixel_data(md),.display_safe_boundary(boundary),
        .front_valid(fv),.front_bank(fb),.front_id(fid),.complete_count(cc),
        .bad_network_packets(bn),.bad_video_packets(bv),.write_available(available));
    always @(posedge clk) if(!rst && mv && ready) begin
        if(ma>=N) $fatal(1,"out of bounds DDR write");
        if(fv && mb==fb) $fatal(1,"FRONT bank overwritten");
        memory[mb*N+ma]<=md;writes<=writes+1;
    end
    function automatic [15:0] pattern(input integer index,input integer id);
        pattern=(index*37+id*257)&65535;
    endfunction
    task automatic display_boundary;
        begin
            repeat(6) @(negedge pclk);
            boundary=1;@(negedge pclk);boundary=0;
            repeat(8) @(negedge clk);
        end
    endtask
    integer f,code,len,v,s,j,k,prior_good,prior_front,expected_complete=0,packets=0;
    initial begin
        repeat(10) @(negedge clk);rst=0;
        repeat(12) @(negedge clk); f=$fopen("vectors.txt","r");if(!f) $fatal(1,"missing vectors");
        while(!$feof(f)) begin
            s=$fscanf(f,"%d %d",code,len);
            if(s==2) begin
                if(code>=0) begin
                    prior_good=dut.network.good_packets;
                    // Exact Ethernet preamble, SFD, frame and FCS fixture.
                    for(j=0;j<len;j=j+1) begin
                        s=$fscanf(f,"%h",v);if(s!=1) $fatal(1,"fixture truncated");
                        @(negedge clk);gv=1;gd=v;
                    end
                    @(negedge clk);gv=0;
                    repeat(400) @(negedge clk);   // CLAUDE: checked_media_ethernet_rx3 now stores and forwards (counter later than the 2026-10-21 module)
                    if(dut.network.good_packets!=prior_good+code)
                        $fatal(1,"network validation packet=%0d expected=%0d",packets,code);
                    packets=packets+1;
                    repeat(9) @(negedge clk);
                end else if(code==-1) begin
                    // Last data accepted into modeled DDR but not committed.
                    repeat(1000) @(negedge clk);
                    if(cc!=expected_complete) $fatal(1,"published before DDR drain");
                    prior_front=fid;
                    drained=1;repeat(16) @(negedge clk);
                    expected_complete=expected_complete+1;
                    if(cc!=expected_complete || fid!=prior_front)
                        $fatal(1,"publish count or unsafe front swap");
                    display_boundary();
                    if(!fv || fid!=len || !available) begin $display("fv=%0d fid=%0d len=%0d avail=%0d cc=%0d", fv, fid, len, available, cc); $fatal(1,"front metadata"); end
                    for(k=0;k<N;k=k+1) begin
                        if(memory[fb*N+k]!==pattern(k,len)) $fatal(1,"DDR image %0d FID %0d",k,len);
                        checks=checks+1;
                    end
                    drained=0;
                end else if(code==-2) begin
                    repeat(1000) @(negedge clk);drained=1;
                    repeat(16) @(negedge clk);prior_front=fid;display_boundary();
                    if(cc!=expected_complete || fid!=prior_front) $fatal(1,"partial/bad frame published");
                    drained=0;checks=checks+1;
                end else if(code==-5)begin ready=len!=0; repeat(10)@(negedge clk); end else if(code==-3) begin
                    rst=1;repeat(8) @(negedge clk);rst=0;
                    repeat(8) @(negedge pclk);
                    if(fv || cc!=0 || !available) $fatal(1,"common reset ownership");
                    expected_complete=0;checks=checks+1;
                end
            end
        end
        $fclose(f);
        $display("CANDIDATE2_INGRESS_REJECT_DRAIN_SWAP_RESET_FINITE_PASS packets=%0d pixels_checked=%0d writes=%0d",packets,checks,writes);
        $finish;
    end
    initial begin #200000000; $fatal(1,"watchdog"); end
endmodule
