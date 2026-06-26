module bridge(
    input  hclk, hreset_n, hselapb, hwrite,
    input  [1:0]  htrans,
    input  [31:0] haddr, hwdata,
    input  [31:0] prdata,
    output reg        hready,
    output reg [31:0] hrdata,
    output reg        psel, penable, pwrite,
    output reg [31:0] paddr, pwdata
);

parameter idle      = 3'b000,
          read      = 3'b001,
          wwait     = 3'b010,
          write     = 3'b011,
          write_p   = 3'b100,
          wenable_p = 3'b101,
          wenable   = 3'b110,
          renable   = 3'b111;

reg [31:0] haddr_r, hwdata_r;   
reg        hwrite_r, valid_r;

reg [2:0]  present_state, next_state;
reg        valid;

always @(*) valid = hselapb && (htrans == 2'b10 || htrans == 2'b11);


always @(posedge hclk or negedge hreset_n) begin
    if (!hreset_n) present_state <= idle;
    else           present_state <= next_state;
end


always @(posedge hclk or negedge hreset_n) begin
    if (!hreset_n) begin
        haddr_r  <= 32'b0;
        hwdata_r <= 32'b0;
        hwrite_r <= 1'b0;
        valid_r  <= 1'b0;
    end else begin
        haddr_r  <= haddr;
        hwdata_r <= hwdata;
        hwrite_r <= hwrite;
        valid_r  <= valid;
    end
end


always @(*) begin
    psel       = 1'b0;
    penable    = 1'b0;
    pwrite     = 1'b0;
    hready     = 1'b0;
    paddr      = 32'b0;
    pwdata     = 32'b0;
    hrdata     = 32'b0;
    next_state = idle;

    case (present_state)

       
        idle: begin
            hready = 1'b1;
            if      (valid && !hwrite) next_state = read;
            else if (valid &&  hwrite) next_state = wwait;
            else                       next_state = idle;
        end

        
        read: begin
            psel       = 1'b1;
            paddr      = haddr_r;   // captured from IDLE cycle
            pwrite     = 1'b0;
            penable    = 1'b0;
            hready     = 1'b0;
            next_state = renable;
        end


        renable: begin
            psel    = 1'b1;
            paddr   = haddr_r;   // see note above
            pwrite  = 1'b0;
            penable = 1'b1;
            hrdata  = prdata;
            hready  = 1'b1;
            // valid_r = what master drove during READ state (new address phase)
            if      (valid_r && !hwrite_r) next_state = read;
            else if (valid_r &&  hwrite_r) next_state = wwait;
            else                           next_state = idle;
        end
        wwait: begin
            hready     = 1'b0;
            psel       = 1'b0;
            penable    = 1'b0;
            if (!valid) next_state = write;
            else        next_state = write_p;
        end

 
        write: begin
            psel    = 1'b1;
            paddr   = haddr_r;
            pwdata  = hwdata_r;
            pwrite  = 1'b1;
            penable = 1'b0;
            hready  = 1'b0;
            if (!valid) next_state = wenable;
            else        next_state = wenable_p;
        end

        write_p: begin
            psel       = 1'b1;
            paddr      = haddr_r;
            pwdata     = hwdata_r;
            pwrite     = 1'b1;
            penable    = 1'b0;
            hready     = 1'b0;
            next_state = wenable_p;
        end

        wenable: begin
            psel    = 1'b1;
            paddr   = haddr_r;
            pwdata  = hwdata_r;
            pwrite  = 1'b1;
            penable = 1'b1;
            hready  = 1'b1;
            if      (valid_r && !hwrite_r) next_state = read;
            else if (valid_r &&  hwrite_r) next_state = wwait;
            else                           next_state = idle;
        end

  
        wenable_p: begin
            psel    = 1'b1;
            paddr   = haddr_r;
            pwdata  = hwdata_r;
            pwrite  = 1'b1;
            penable = 1'b1;
            hready  = 1'b1;
            if      (!valid_r &&  hwrite_r) next_state = write;
            else if ( valid_r &&  hwrite_r) next_state = write_p;
            else if ( valid_r && !hwrite_r) next_state = read;
            else                            next_state = idle;
        end

        default: next_state = idle;

    endcase
end

endmodule
