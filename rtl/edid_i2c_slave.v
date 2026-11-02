`timescale 1ns / 1ps
// 内部 EDID I2C 从机（含 CEA 扩展：LPCM 2ch 48kHz）
module edid_i2c_slave (
    input  wire clk,
    input  wire rst_n,
    input  wire scl,
    input  wire sda_in,
    output reg  sda_low
);

reg [7:0] edid_rom [0:255];
initial begin
    edid_rom[  0] = 8'h00;
    edid_rom[  1] = 8'hFF;
    edid_rom[  2] = 8'hFF;
    edid_rom[  3] = 8'hFF;
    edid_rom[  4] = 8'hFF;
    edid_rom[  5] = 8'hFF;
    edid_rom[  6] = 8'hFF;
    edid_rom[  7] = 8'h00;
    edid_rom[  8] = 8'h31;
    edid_rom[  9] = 8'hD8;
    edid_rom[ 10] = 8'h34;
    edid_rom[ 11] = 8'h12;
    edid_rom[ 12] = 8'h00;
    edid_rom[ 13] = 8'h00;
    edid_rom[ 14] = 8'h00;
    edid_rom[ 15] = 8'h00;
    edid_rom[ 16] = 8'h01;
    edid_rom[ 17] = 8'h1E;
    edid_rom[ 18] = 8'h01;
    edid_rom[ 19] = 8'h03;
    edid_rom[ 20] = 8'h80;
    edid_rom[ 21] = 8'h1E;
    edid_rom[ 22] = 8'h17;
    edid_rom[ 23] = 8'h78;
    edid_rom[ 24] = 8'h0A;
    edid_rom[ 25] = 8'hEE;
    edid_rom[ 26] = 8'h91;
    edid_rom[ 27] = 8'hA3;
    edid_rom[ 28] = 8'h54;
    edid_rom[ 29] = 8'h4C;
    edid_rom[ 30] = 8'h99;
    edid_rom[ 31] = 8'h26;
    edid_rom[ 32] = 8'h0F;
    edid_rom[ 33] = 8'h50;
    edid_rom[ 34] = 8'h54;
    edid_rom[ 35] = 8'h20;
    edid_rom[ 36] = 8'h00;
    edid_rom[ 37] = 8'h00;
    edid_rom[ 38] = 8'h01;
    edid_rom[ 39] = 8'h01;
    edid_rom[ 40] = 8'h01;
    edid_rom[ 41] = 8'h01;
    edid_rom[ 42] = 8'h01;
    edid_rom[ 43] = 8'h01;
    edid_rom[ 44] = 8'h01;
    edid_rom[ 45] = 8'h01;
    edid_rom[ 46] = 8'h01;
    edid_rom[ 47] = 8'h01;
    edid_rom[ 48] = 8'h01;
    edid_rom[ 49] = 8'h01;
    edid_rom[ 50] = 8'h01;
    edid_rom[ 51] = 8'h01;
    edid_rom[ 52] = 8'h01;
    edid_rom[ 53] = 8'h01;
    edid_rom[ 54] = 8'hD5;
    edid_rom[ 55] = 8'h09;
    edid_rom[ 56] = 8'h80;
    edid_rom[ 57] = 8'hA0;
    edid_rom[ 58] = 8'h20;
    edid_rom[ 59] = 8'hE0;
    edid_rom[ 60] = 8'h2D;
    edid_rom[ 61] = 8'h10;
    edid_rom[ 62] = 8'h10;
    edid_rom[ 63] = 8'h60;
    edid_rom[ 64] = 8'hA2;
    edid_rom[ 65] = 8'h00;
    edid_rom[ 66] = 8'hA0;
    edid_rom[ 67] = 8'h78;
    edid_rom[ 68] = 8'h00;
    edid_rom[ 69] = 8'h00;
    edid_rom[ 70] = 8'h00;
    edid_rom[ 71] = 8'h1A;
    edid_rom[ 72] = 8'h00;
    edid_rom[ 73] = 8'h00;
    edid_rom[ 74] = 8'h00;
    edid_rom[ 75] = 8'h10;
    edid_rom[ 76] = 8'h00;
    edid_rom[ 77] = 8'h00;
    edid_rom[ 78] = 8'h00;
    edid_rom[ 79] = 8'h00;
    edid_rom[ 80] = 8'h00;
    edid_rom[ 81] = 8'h00;
    edid_rom[ 82] = 8'h00;
    edid_rom[ 83] = 8'h00;
    edid_rom[ 84] = 8'h00;
    edid_rom[ 85] = 8'h00;
    edid_rom[ 86] = 8'h00;
    edid_rom[ 87] = 8'h00;
    edid_rom[ 88] = 8'h00;
    edid_rom[ 89] = 8'h00;
    edid_rom[ 90] = 8'h00;
    edid_rom[ 91] = 8'h00;
    edid_rom[ 92] = 8'h00;
    edid_rom[ 93] = 8'h10;
    edid_rom[ 94] = 8'h00;
    edid_rom[ 95] = 8'h00;
    edid_rom[ 96] = 8'h00;
    edid_rom[ 97] = 8'h00;
    edid_rom[ 98] = 8'h00;
    edid_rom[ 99] = 8'h00;
    edid_rom[100] = 8'h00;
    edid_rom[101] = 8'h00;
    edid_rom[102] = 8'h00;
    edid_rom[103] = 8'h00;
    edid_rom[104] = 8'h00;
    edid_rom[105] = 8'h00;
    edid_rom[106] = 8'h00;
    edid_rom[107] = 8'h00;
    edid_rom[108] = 8'h00;
    edid_rom[109] = 8'h00;
    edid_rom[110] = 8'h00;
    edid_rom[111] = 8'h10;
    edid_rom[112] = 8'h00;
    edid_rom[113] = 8'h00;
    edid_rom[114] = 8'h00;
    edid_rom[115] = 8'h00;
    edid_rom[116] = 8'h00;
    edid_rom[117] = 8'h00;
    edid_rom[118] = 8'h00;
    edid_rom[119] = 8'h00;
    edid_rom[120] = 8'h00;
    edid_rom[121] = 8'h00;
    edid_rom[122] = 8'h00;
    edid_rom[123] = 8'h00;
    edid_rom[124] = 8'h00;
    edid_rom[125] = 8'h00;
    edid_rom[126] = 8'h01;
    edid_rom[127] = 8'h49;
    edid_rom[128] = 8'h02;
    edid_rom[129] = 8'h03;
    edid_rom[130] = 8'h00;
    edid_rom[131] = 8'h00;
    edid_rom[132] = 8'h23;
    edid_rom[133] = 8'h09;
    edid_rom[134] = 8'h04;
    edid_rom[135] = 8'h07;
    edid_rom[136] = 8'h00;
    edid_rom[137] = 8'h00;
    edid_rom[138] = 8'h00;
    edid_rom[139] = 8'h00;
    edid_rom[140] = 8'h00;
    edid_rom[141] = 8'h00;
    edid_rom[142] = 8'h00;
    edid_rom[143] = 8'h00;
    edid_rom[144] = 8'h00;
    edid_rom[145] = 8'h00;
    edid_rom[146] = 8'h00;
    edid_rom[147] = 8'h00;
    edid_rom[148] = 8'h00;
    edid_rom[149] = 8'h00;
    edid_rom[150] = 8'h00;
    edid_rom[151] = 8'h00;
    edid_rom[152] = 8'h00;
    edid_rom[153] = 8'h00;
    edid_rom[154] = 8'h00;
    edid_rom[155] = 8'h00;
    edid_rom[156] = 8'h00;
    edid_rom[157] = 8'h00;
    edid_rom[158] = 8'h00;
    edid_rom[159] = 8'h00;
    edid_rom[160] = 8'h00;
    edid_rom[161] = 8'h00;
    edid_rom[162] = 8'h00;
    edid_rom[163] = 8'h00;
    edid_rom[164] = 8'h00;
    edid_rom[165] = 8'h00;
    edid_rom[166] = 8'h00;
    edid_rom[167] = 8'h00;
    edid_rom[168] = 8'h00;
    edid_rom[169] = 8'h00;
    edid_rom[170] = 8'h00;
    edid_rom[171] = 8'h00;
    edid_rom[172] = 8'h00;
    edid_rom[173] = 8'h00;
    edid_rom[174] = 8'h00;
    edid_rom[175] = 8'h00;
    edid_rom[176] = 8'h00;
    edid_rom[177] = 8'h00;
    edid_rom[178] = 8'h00;
    edid_rom[179] = 8'h00;
    edid_rom[180] = 8'h00;
    edid_rom[181] = 8'h00;
    edid_rom[182] = 8'h00;
    edid_rom[183] = 8'h00;
    edid_rom[184] = 8'h00;
    edid_rom[185] = 8'h00;
    edid_rom[186] = 8'h00;
    edid_rom[187] = 8'h00;
    edid_rom[188] = 8'h00;
    edid_rom[189] = 8'h00;
    edid_rom[190] = 8'h00;
    edid_rom[191] = 8'h00;
    edid_rom[192] = 8'h00;
    edid_rom[193] = 8'h00;
    edid_rom[194] = 8'h00;
    edid_rom[195] = 8'h00;
    edid_rom[196] = 8'h00;
    edid_rom[197] = 8'h00;
    edid_rom[198] = 8'h00;
    edid_rom[199] = 8'h00;
    edid_rom[200] = 8'h00;
    edid_rom[201] = 8'h00;
    edid_rom[202] = 8'h00;
    edid_rom[203] = 8'h00;
    edid_rom[204] = 8'h00;
    edid_rom[205] = 8'h00;
    edid_rom[206] = 8'h00;
    edid_rom[207] = 8'h00;
    edid_rom[208] = 8'h00;
    edid_rom[209] = 8'h00;
    edid_rom[210] = 8'h00;
    edid_rom[211] = 8'h00;
    edid_rom[212] = 8'h00;
    edid_rom[213] = 8'h00;
    edid_rom[214] = 8'h00;
    edid_rom[215] = 8'h00;
    edid_rom[216] = 8'h00;
    edid_rom[217] = 8'h00;
    edid_rom[218] = 8'h00;
    edid_rom[219] = 8'h00;
    edid_rom[220] = 8'h00;
    edid_rom[221] = 8'h00;
    edid_rom[222] = 8'h00;
    edid_rom[223] = 8'h00;
    edid_rom[224] = 8'h00;
    edid_rom[225] = 8'h00;
    edid_rom[226] = 8'h00;
    edid_rom[227] = 8'h00;
    edid_rom[228] = 8'h00;
    edid_rom[229] = 8'h00;
    edid_rom[230] = 8'h00;
    edid_rom[231] = 8'h00;
    edid_rom[232] = 8'h00;
    edid_rom[233] = 8'h00;
    edid_rom[234] = 8'h00;
    edid_rom[235] = 8'h00;
    edid_rom[236] = 8'h00;
    edid_rom[237] = 8'h00;
    edid_rom[238] = 8'h00;
    edid_rom[239] = 8'h00;
    edid_rom[240] = 8'h00;
    edid_rom[241] = 8'h00;
    edid_rom[242] = 8'h00;
    edid_rom[243] = 8'h00;
    edid_rom[244] = 8'h00;
    edid_rom[245] = 8'h00;
    edid_rom[246] = 8'h00;
    edid_rom[247] = 8'h00;
    edid_rom[248] = 8'h00;
    edid_rom[249] = 8'h00;
    edid_rom[250] = 8'h00;
    edid_rom[251] = 8'h00;
    edid_rom[252] = 8'h00;
    edid_rom[253] = 8'h00;
    edid_rom[254] = 8'h00;
    edid_rom[255] = 8'hC4;
end

reg [2:0] scl_s;
reg [2:0] sda_s;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        scl_s <= 3'b111;
        sda_s <= 3'b111;
    end else begin
        scl_s <= {scl_s[1:0], scl};
        sda_s <= {sda_s[1:0], sda_in};
    end
end

wire scl_rise =  scl_s[1] & ~scl_s[2];
wire scl_fall = ~scl_s[1] &  scl_s[2];
wire sda_now  =  sda_s[1];
wire start_c  = ( scl_s[2] &  scl_s[1]) & (~sda_s[2] &  sda_s[1]);
wire stop_c   = ( scl_s[2] &  scl_s[1]) & ( sda_s[2] & ~sda_s[1]);

localparam S_IDLE = 2'd0, S_ADDR = 2'd1, S_SUB = 2'd2, S_TX = 2'd3;

reg [1:0] state;
reg [3:0] bitpos;
reg [7:0] shift;
reg [7:0] sub_addr;
reg [7:0] byte_idx;
reg [7:0] tx_byte;
reg       rd_next;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state    <= S_IDLE;
        bitpos   <= 4'd0;
        shift    <= 8'd0;
        sub_addr <= 8'd0;
        byte_idx <= 8'd0;
        tx_byte  <= 8'd0;
        rd_next  <= 1'b0;
        sda_low  <= 1'b0;
    end else if (start_c) begin
        state   <= S_ADDR;
        bitpos  <= 4'd0;
        shift   <= 8'd0;
        sda_low <= 1'b0;
    end else if (stop_c) begin
        state   <= S_IDLE;
        bitpos  <= 4'd0;
        sda_low <= 1'b0;
    end else begin
        case (state)
        S_IDLE: sda_low <= 1'b0;

        S_ADDR: begin
            if (scl_rise) begin
                if (bitpos < 4'd8) shift <= {shift[6:0], sda_now};
                if (bitpos == 4'd7) rd_next <= sda_now;
                bitpos <= bitpos + 1'b1;
            end else if (scl_fall) begin
                if (bitpos == 4'd8) begin
                    sda_low <= 1'b1;
                end else if (bitpos == 4'd9) begin
                    sda_low <= 1'b0;
                    bitpos  <= 4'd0;
                    if (shift[7:1] == 7'h50) begin
                        if (rd_next) begin
                            state    <= S_TX;
                            byte_idx <= sub_addr;
                            tx_byte  <= edid_rom[sub_addr];
                            sda_low  <= ~edid_rom[sub_addr][7];
                        end else begin
                            state <= S_SUB;
                        end
                    end else begin
                        state <= S_IDLE;
                    end
                end
            end
        end

        S_SUB: begin
            if (scl_rise) begin
                if (bitpos < 4'd8) shift <= {shift[6:0], sda_now};
                bitpos <= bitpos + 1'b1;
            end else if (scl_fall) begin
                if (bitpos == 4'd8) begin
                    sda_low <= 1'b1;
                end else if (bitpos == 4'd9) begin
                    sda_low  <= 1'b0;
                    bitpos   <= 4'd0;
                    sub_addr <= shift;
                    state    <= S_ADDR;
                end
            end
        end

        S_TX: begin
            if (scl_fall) begin
                if (bitpos < 4'd7) begin
                    sda_low <= ~tx_byte[6 - bitpos];
                    bitpos  <= bitpos + 1'b1;
                end else if (bitpos == 4'd7) begin
                    sda_low <= 1'b0;
                    bitpos  <= 4'd8;
                end else begin
                    tx_byte  <= edid_rom[byte_idx + 8'd1];
                    byte_idx <= byte_idx + 8'd1;
                    sda_low  <= ~edid_rom[byte_idx + 8'd1][7];
                    bitpos   <= 4'd0;
                end
            end
        end
        endcase
    end
end

endmodule

