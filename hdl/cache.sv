module cache (
    input   logic           clk,
    input   logic           rst,

    // cpu side signals, ufp -> upward facing port
    input   logic   [31:0]  ufp_addr,
    input   logic   [3:0]   ufp_rmask,
    input   logic   [3:0]   ufp_wmask,
    output  logic   [31:0]  ufp_rdata,
    input   logic   [31:0]  ufp_wdata,
    output  logic           ufp_resp,

    // memory side signals, dfp -> downward facing port
    output  logic   [31:0]  dfp_addr,
    output  logic           dfp_read,
    output  logic           dfp_write,
    input   logic   [255:0] dfp_rdata,
    output  logic   [255:0] dfp_wdata,
    input   logic           dfp_resp
);
    logic [22:0] ufp_tag;
    logic [3:0] ufp_idx;
    logic [4:0] ufp_offset;
    assign ufp_tag = ufp_addr[31:9];
    assign ufp_idx = ufp_addr[8:5];
    assign ufp_offset = {ufp_addr[4:2], 2'b00};

    //Array outputs
    logic data_we [4];
    logic [255:0] data_in [4];
    logic [255:0] data_array_dout [4];
    logic tag_we [4];
    logic [23:0] tag_in [4];
    logic [23:0] tag_array_dout [4];
    logic valid_in [4];
    logic valid_we [4];
    logic valid_array_dout [4];

    //Hit detect and way finder
    logic [1:0] way_select [16];
    logic [3:0] tag_equal;
    logic and0, and1, and2, and3;
    logic hit_detected;
    logic [255:0] data;

    //FSM signals
    enum int unsigned {IDLE, CMP, ALLOCATE, WAIT, WRITEBACK} fsm_state, fsm_next_state;

    //PLRU signals
    logic [1:0] way_PLRU [16];
    logic [2:0] PLRU [16];
    logic [2:0] PLRU_out [16];
    logic [31:0] cache_wmask;

    //In which Way do we have a Hit?
    //Example: ufp_tag compared to the tag_array we referenced from memory
    //         ufp_tag = tag_array_dout[3], meaning hit in Way 3
    //         Hit_detected = 1, way_select (Way that it is located in) = 11 = 3, then they're combined
    always_comb begin
        for(int i = 0; i < 16; i++) begin
            way_select[i] = 'x;
        end
        if(ufp_tag == tag_array_dout[0][22:0]) begin
            tag_equal[0] = 1'b1;
            way_select[ufp_idx] = 2'b00;
        end
        else begin 
            tag_equal[0] = 1'b0;
            //way_select[ufp_idx] = 'x;
        end
        if(ufp_tag == tag_array_dout[1][22:0]) begin
            tag_equal[1] = 1'b1;
            way_select[ufp_idx] = 2'b01;
        end
        else begin 
            tag_equal[1] = 1'b0;
            //way_select[ufp_idx] = 'x;
        end
        if(ufp_tag == tag_array_dout[2][22:0])begin
            tag_equal[2] = 1'b1;
            way_select[ufp_idx] = 2'b10;
        end
        else begin 
            tag_equal[2] = 1'b0;
            //way_select[ufp_idx] = 'x;
        end
        if(ufp_tag == tag_array_dout[3][22:0])begin
            tag_equal[3] = 1'b1;
            way_select[ufp_idx] = 2'b11;
        end
        else begin 
            tag_equal[3] = 1'b0;
            //way_select[ufp_idx] = 'x;
        end

        and0 = tag_equal[0] & valid_array_dout[0];
        and1 = tag_equal[1] & valid_array_dout[1];
        and2 = tag_equal[2] & valid_array_dout[2];
        and3 = tag_equal[3] & valid_array_dout[3];

        if(and0) begin
            data = data_array_dout[0];
        end
        else if(and1) begin
            data = data_array_dout[1];
        end
        else if(and2) begin
            data = data_array_dout[2];
        end
        else if(and3) begin
            data = data_array_dout[3];
        end
        else begin
            data = 'x;
        end

        if(and0 || and1 || and2 || and3) begin
            hit_detected = 1'b1;
        end
        else hit_detected = 1'b0;

        /*if(tag_equal == 4'b1000) way_select[ufp_idx] = 2'b11;
        else if(tag_equal == 4'b0100) way_select[ufp_idx] = 2'b10;
        else if(tag_equal == 4'b0010) way_select[ufp_idx] = 2'b01;
        else if(tag_equal == 4'b0001) way_select[ufp_idx] = 2'b00;
        else way_select[ufp_idx] = 'x;*/

    end

    logic[31:0] data_temp;
    logic[31:0] cache_wdata;
    logic [255:0] data_input;
    logic [31:0] data_read_temp;

    always_ff @(posedge clk) begin
        if(rst) begin
            fsm_state <= IDLE;
            for(int i = 0; i < 16; i++) begin
                PLRU[i] <= 3'b000;
                way_PLRU[i] <= 2'b11;
            end
        end
        else begin
            fsm_state <= fsm_next_state;
            for(int i = 0; i < 16; i++) begin
                PLRU[i] <= PLRU_out[i];
            end
            if((PLRU[ufp_idx][2] == 1'b0) && (PLRU[ufp_idx][0] == 1'b0)) begin
                //if(hit_detected)
                    way_PLRU[ufp_idx] <= 2'b11; //WAY D
            end
            else if((PLRU[ufp_idx][2] == 1'b1) && (PLRU[ufp_idx][0] == 1'b0)) begin
                //if(hit_detected)
                    way_PLRU[ufp_idx] <= 2'b10; //wAY C
            end
            else if((PLRU[ufp_idx][1] == 1'b0) && (PLRU[ufp_idx][0] == 1'b1)) begin
                //if(hit_detected)
                    way_PLRU[ufp_idx] <= 2'b01; //WAY B
            end
            else if((PLRU[ufp_idx][1] == 1'b1) && (PLRU[ufp_idx][0] == 1'b1)) begin
                //if(hit_detected)
                    way_PLRU[ufp_idx] <= 2'b00; //WAY A
            end
        end
    end

    /*assign cache_rdata = data_array_dout[way_select];
    //rdata: translated from a 256 bit (32B) output of the memory into a 32 bit output to CPU
    // memory -> data_array (256) -> cache_rdata (256) -> ufp_rdata (32) 
    assign ufp_rdata = cache_rdata[(32 * ufp_addr[4:2]) +: 32];
    //wdata: translated from a 32 bit input from CPU to 256 bit (32B) input into the memory
    // cpu -> ufp_wdata (32) -> cache_wdata (256) -> dfp_wdata (256)
    assign cache_wdata = {8{ufp_wdata}};
    //wmask: translated from a 4 bit input from CPU to 32 bit input into the data array
    // cpu -> ufp_wmask (4) -> cache_wmask (4) -> data_array .wmask0()
    assign cache_wmask = {28'h0, ufp_wmask} << (ufp_addr[4:2] * 4);
    */
    //FSM
    

    always_comb begin 
        //set defaults
        fsm_next_state = IDLE;
        ufp_resp = 1'b0;
        ufp_rdata = '0;
        dfp_addr = 'x;
        dfp_read = 1'b0;
        dfp_write = 1'b0;
        dfp_wdata = 'x;
        cache_wmask = 32'b0;
        cache_wdata = '0;

        tag_in[0] = 'x;
        tag_in[1] = 'x;
        tag_in[2] = 'x;
        tag_in[3] = 'x;
        data_we[0] = 1'b1;
        data_we[1] = 1'b1;
        data_we[2] = 1'b1;
        data_we[3] = 1'b1;
        data_in[0] = 'x;
        data_in[1] = 'x;
        data_in[2] = 'x;
        data_in[3] = 'x;
        valid_we[0] = 1'b1;
        valid_we[1] = 1'b1;
        valid_we[2] = 1'b1;
        valid_we[3] = 1'b1;
        valid_in[0] = 'x;
        valid_in[1] = 'x;
        valid_in[2] = 'x;
        valid_in[3] = 'x;
        tag_we[0] = 1'b1;
        tag_we[1] = 1'b1;
        tag_we[2] = 1'b1;
        tag_we[3] = 1'b1;
        data_read_temp = '0;
        
        PLRU_out = PLRU;

        unique case(fsm_state)
            IDLE: begin
                if((ufp_rmask != 4'b0000) || (ufp_wmask != 4'b0000))
                    fsm_next_state = CMP;
                else
                    fsm_next_state = IDLE;
            end
            CMP: begin
                if(hit_detected) begin
                    valid_in[way_select[ufp_idx]] = 1'b1;
                    valid_we[way_select[ufp_idx]] = 1'b0;
                    tag_we[way_select[ufp_idx]] = 1'b0;
                    if(ufp_wmask != 4'b0000) begin
                        tag_in[way_select[ufp_idx]] = {1'b1, ufp_tag};
                        cache_wmask = 32'hffffffff;
                        data_temp = data[ufp_offset*8+:32];
                        data_input = data;
                        if(ufp_wmask[3]) 
                            cache_wdata[31:24] = ufp_wdata[31:24];
                        else
                            cache_wdata[31:24] = data_temp[31:24];
                        if(ufp_wmask[2]) 
                            cache_wdata[23:16] = ufp_wdata[23:16];
                        else
                            cache_wdata[23:16] = data_temp[23:16];
                        if(ufp_wmask[1]) 
                            cache_wdata[15:8] = ufp_wdata[15:8];
                        else
                            cache_wdata[15:8] = data_temp[15:8];
                        if(ufp_wmask[0]) 
                            cache_wdata[7:0] = ufp_wdata[7:0];
                        else
                            cache_wdata[7:0] = data_temp[7:0];
                        data_input[ufp_offset*8+:32] = cache_wdata;
                        data_in[way_select[ufp_idx]] = data_input;
                        data_we[way_select[ufp_idx]] = 1'b0;
                        ufp_resp = 1'b1;
                    end
                    else begin
                        tag_in[way_select[ufp_idx]] = {tag_array_dout[way_select[ufp_idx]][23], ufp_tag}; //the read hit doesn't necessarily set dirty bit to 0, since it could hit a write
                        ufp_resp = 1'b1;
                        data_read_temp = data_array_dout[way_select[ufp_idx]][(32*ufp_offset[4:2]) +: 32];
                        if(ufp_rmask[3])
                            ufp_rdata[31:24] = data_read_temp[31:24];
                        if(ufp_rmask[2])
                            ufp_rdata[23:16] = data_read_temp[23:16];
                        if(ufp_rmask[1])
                            ufp_rdata[15:8] = data_read_temp[15:8];
                        if(ufp_rmask[0])
                            ufp_rdata[7:0] = data_read_temp[7:0];
                    end
                    if(way_select[ufp_idx] == 2'b00) begin //WAY A 
                        //[0] AB/CD = 0, [1] AB = 0, [2] CD = x
                        PLRU_out[ufp_idx][1] = 1'b0;
                        PLRU_out[ufp_idx][0] = 1'b0;
                    end
                    else if(way_select[ufp_idx] == 2'b01) begin //WAY B
                        //[0] AB/CD = 0, [1] AB = 1, [2] CD = x
                        PLRU_out[ufp_idx][1] = 1'b1;
                        PLRU_out[ufp_idx][0] = 1'b0;
                    end
                    else if(way_select[ufp_idx] == 2'b10) begin //WAY C
                        //[0] AB/CD = 1, [1] AB = x, [2] CD = 0
                        PLRU_out[ufp_idx][2] = 1'b0; 
                        PLRU_out[ufp_idx][0] = 1'b1;
                    end
                    else if(way_select[ufp_idx] == 2'b11) begin //WAY D
                        //[0] AB/CD = 1, [1] AB = x, [2] CD = 1
                       PLRU_out[ufp_idx][2] = 1'b1; 
                       PLRU_out[ufp_idx][0] = 1'b1;
                    end
                    fsm_next_state = IDLE;
                end
                //If the tags aren't equal, no hit
                //If the dirty bit is 0, that means that there's no write to evict, so we have to allocate
                else if(tag_equal[way_PLRU[ufp_idx]] == 1'b0 && tag_array_dout[way_PLRU[ufp_idx]][23] == 1'b0) begin
                    data_we[way_PLRU[ufp_idx]] = 1'b1;

                    fsm_next_state = ALLOCATE;
                end
                //No hit, but the cacheline was set dirty by a previous write that we now have to writeback in order to evict
                else if (tag_equal[way_PLRU[ufp_idx]] == 1'b0 && tag_array_dout[way_PLRU[ufp_idx]][23] == 1'b1) begin
                    data_we[way_PLRU[ufp_idx]] = 1'b1;
                    fsm_next_state = WRITEBACK;
                end
                else begin
                    data_we[way_PLRU[ufp_idx]] = 1'b1;

                    fsm_next_state = ALLOCATE;
                end
            end
            ALLOCATE: begin
                dfp_read = 1'b1;
                dfp_addr = {ufp_addr[31:5], 5'b00000};
                if(dfp_resp) begin
                    cache_wmask = 32'hffffffff;
                    if(way_PLRU[ufp_idx] == 2'b00) begin
                        data_in[0] = dfp_rdata; //WAY A 
                        data_we[0] = 1'b0;
                        valid_in[0] = 1'b1;
                        valid_we[0] = 1'b0;
                        tag_we[0] = 1'b0;
                        tag_in[0] = {1'b0, ufp_tag}; //whenever we reach allocate, either we read miss, or we just wroteback on a read or write
                        //setting this to 0 is fine, since after a writeback and allocate, we'll go back to CMP
                        //in CMP, if the write was evicted by a read, this stays 0. If it was evicted by another write, we set it dirty again in CMP
                    end
                    else if(way_PLRU[ufp_idx] == 2'b01) begin
                        data_in[1] = dfp_rdata; //WAY B
                        data_we[1] = 1'b0;
                        valid_in[1] = 1'b1;
                        valid_we[1] = 1'b0;
                        tag_we[1] = 1'b0;
                        tag_in[1] = {1'b0, ufp_tag};
                    end
                    else if(way_PLRU[ufp_idx] == 2'b10) begin
                        data_in[2] = dfp_rdata; //WAY C
                        data_we[2] = 1'b0;
                        valid_in[2] = 1'b1;
                        valid_we[2] = 1'b0;
                        tag_we[2] = 1'b0;
                        tag_in[2] = {1'b0, ufp_tag};
                    end
                    else if(way_PLRU[ufp_idx] == 2'b11) begin
                        data_in[3] = dfp_rdata; //WAY D
                        data_we[3] = 1'b0;
                        valid_in[3] = 1'b1;
                        valid_we[3] = 1'b0;
                        tag_we[3] = 1'b0;
                        tag_in[3] = {1'b0, ufp_tag};
                    end
                    fsm_next_state = WAIT;
                end
                else
                    fsm_next_state = ALLOCATE;
            end
            WAIT: begin
                fsm_next_state = CMP;
            end
            WRITEBACK: begin
                dfp_addr = {tag_array_dout[way_PLRU[ufp_idx]][22:0], ufp_idx, 5'b00000};
                dfp_write = 1'b1;
                dfp_wdata = data_array_dout[way_PLRU[ufp_idx]];

                if(dfp_resp) begin
                    fsm_next_state = ALLOCATE;
                end
                else begin
                    fsm_next_state = WRITEBACK;
                end
            end
            default: begin
                fsm_next_state = IDLE;
            end
        endcase
    end

    generate for (genvar i = 0; i < 4; i++) begin : arrays
        mp_cache_data_array data_array (
            .clk0       (clk),
            .csb0       (1'b0),
            .web0       (data_we[i]),
            .wmask0     (cache_wmask),
            .addr0      (ufp_idx),
            .din0       (data_in[i]),
            .dout0      (data_array_dout[i])
        );
        mp_cache_tag_array tag_array (
            .clk0       (clk),
            .csb0       (1'b0),
            .web0       (tag_we[i]),
            .addr0      (ufp_idx),
            .din0       (tag_in[i]),
            .dout0      (tag_array_dout[i])
        );
        ff_array #(.WIDTH(1)) valid_array (
            .clk0       (clk),
            .rst0       (rst),
            .csb0       (1'b0),
            .web0       (valid_we[i]),
            .addr0      (ufp_idx),
            .din0       (valid_in[i]),
            .dout0      (valid_array_dout[i])
        );
    end endgenerate


endmodule
