`timescale 1ns / 1ps
// OSD: 底部字幕 + 状态数字 + 亮度档位 + 音频电平柱条 + 倒车辅助图形
// 电平柱条 / 倒车辅助图形 / 调色板一律复用本模块的同一组输出寄存器，
// 不再单独占用像素合成通路（本工程布局余量极小，多一条 24bit mux
// 就会挤掉 sd_card_clk 域扫描逻辑的布局空间）。
//
// osel 通道选择（由顶层组合产生，本模块只做优先级选择、不打拍，
// 因此不产生额外像素延迟，与原版时序完全一致）：
//   2'd0 倒车辅助图形（最高）
//   2'd1 字幕
//   2'd2 音频电平柱条
//   2'd3 无
module osd_overlay #(
    parameter X0 = 12'd8,
    parameter Y0 = 11'd446
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        de,
    input  wire [11:0] x,
    input  wire [10:0] y,
    input  wire [3:0]  dbg_code,     // SD 状态码
    input  wire [3:0]  dbg_code2,    // 亮度档位
    input  wire [2:0]  dbg_cnt,      // 调试：扫描到的合格图片张数
    input  wire [4:0]  audio_lvl,    // 实时音频电平 0..31

    // ---- 倒车辅助 ----
    input  wire [1:0]  osel,         // 通道选择（见上）
    input  wire [2:0]  pal_sel,      // 调色板索引 0..7
    input  wire [1:0]  lvl,          // 预警分级 0..3
    input  wire [1:0]  dist_sel,     // 距离档 0..3（200/120/60/20cm）
    input  wire        ra_en,        // 倒车辅助模式使能

    output reg         osd_on,
    output reg  [23:0] osd_rgb
);
    localparam NCHAR = 21;
    wire [3:0]  row  = (y >= Y0) ? (y - Y0) : 4'd0;
    wire [12:0] dx   = (x >= X0) ? (x - X0) : 13'd0;
    wire [4:0]  cpos = dx[12:4];
    wire [3:0]  col  = dx[3:0];

    function [5:0] char_at(input [4:0] p);
        begin
            case (p)
            0: char_at = 6'd13;
            1: char_at = 6'd14;
            2: char_at = 6'd15;
            3: char_at = 6'd16;
            4: char_at = 6'd17;
            5: char_at = 6'd18;
            6: char_at = 6'd19;
            7: char_at = 6'd20;
            8: char_at = 6'd0;
            9: char_at = 6'd0;
            10: char_at = 6'd21;
            11: char_at = 6'd22;
            12: char_at = 6'd23;
            13: char_at = 6'd24;
                default: char_at = 6'd0;
            endcase
        end
    endfunction

    wire [5:0] cc = (cpos < 5'd14) ? char_at(cpos)                :
                    (cpos == 5'd14) ? 6'd0                        :
                    (cpos == 5'd15) ? (6'd3 + {2'b0, dbg_code})   :
                    (cpos == 5'd16) ? (6'd3 + {2'b0, dbg_code2})  :
                    (cpos == 5'd20) ? (6'd3 + {3'b0, dbg_cnt})    :
                                     6'd0;

    // ---- 倒车辅助距离数字：3 位（百/十/个），复用字模 char 3..12 = '0'..'9' ----
    // 窗口 y 26..41，x 288..335（每位 16px）
    // 距离档 -> 三位数字（组合查表，避免任何除法/乘法）
    //   dist_sel 0 = 200 / 1 = 120 / 2 = 060 / 3 = 020
    // 注意：个位恒为 0，因此只需 2 个 4bit 电阻。
    wire [3:0] d100 = (dist_sel == 2'd0) ? 4'd2 :
                      (dist_sel == 2'd1) ? 4'd1 : 4'd0;
    wire [3:0] d10  = (dist_sel == 2'd1) ? 4'd2 :
                      (dist_sel == 2'd2) ? 4'd6 :
                      (dist_sel == 2'd3) ? 4'd2 : 4'd0;
    wire [3:0] d1   = 4'd0;

    // 距离数字 3 位（百/十/个）：x 288..335（每位 16px）
    wire        num_win = (y >= 11'd26) & (y < 11'd42) & (x >= 12'd288) & (x < 12'd336);
    wire [3:0]  num_dig = (x < 12'd304) ? d100 :
                          (x < 12'd320) ? d10  : d1;
    wire [5:0]  num_char = 6'd3 + {2'b0, num_dig};

    // 字模 ROM 输入：倒车数字窗口优先，否则走字幕通道（单口组合 ROM，用 mux 复用）
    // 数字窗口左边界用 288：288/16 = 18，整字对齐
    wire [3:0]  num_col  = (x - 12'd288) & 4'hF;
    wire [5:0]  font_char = num_win ? num_char : cc;
    wire [3:0]  font_row  = num_win ? (y - 11'd26) : row;
    wire [3:0]  font_col  = num_win ? num_col : col;

    wire [15:0] bits;
    osd_font u_font(.char_idx(font_char), .row(font_row), .bits(bits));

    // 音频电平柱条（右下角）：底框 + 实时填充
    wire       bar_bg  = (y >= 11'd420) && (y < 11'd438) && (x >= 12'd480) && (x < 12'd632);
    wire [7:0] bar_len = 8'd4 + {audio_lvl, 2'b00};        // 4..128
    wire bar_fg = (y >= 11'd421) && (y < 11'd437) && (x >= 12'd482) && (x < (12'd482 + {4'd0, bar_len}));

    // ------------------------------------------------------------------
    // 调色板：每级三色（主色 / 暗色 / 高亮），pal_sel 在这里译成 24bit。
    // 这样 4 选 1 的多路器只被 3 份，而不是每个绘制元素各来一份。
    // ------------------------------------------------------------------
    // 三档配色（远处安全用绿，近处危险用红；三档必须肉眼可分）
    //   lvl0 = 200cm 安全：绿    lvl1 = 120cm 注意：黄
    //   lvl2 = 60cm  警告：橙    lvl3 = 20cm  危险：红
    wire [23:0] pal_pri = (lvl == 2'd0) ? 24'h00C800 :
                          (lvl == 2'd1) ? 24'hFFC800 :
                          (lvl == 2'd2) ? 24'hFF7A00 : 24'hFF1E1E;
    wire [23:0] pal_drk = (lvl == 2'd0) ? 24'h00D200 :   // 绿区：实心绿底
                          (lvl == 2'd1) ? 24'h9A7200 :   // 黄区：实心暗黄底
                          (lvl == 2'd2) ? 24'hA03C00 :   // 橙区：实心暗橙底
                                          24'hB00000;    // 危险：暗红底
    wire [23:0] pal_hil = (lvl == 2'd0) ? 24'h7CFF5A :
                          (lvl == 2'd1) ? 24'hFFE87A :
                          (lvl == 2'd2) ? 24'hFFC46B : 24'hFF7A7A;

    reg [23:0] pal_rgb;
    always @(*) begin
        case (pal_sel)
            3'd0:    pal_rgb = pal_pri;
            3'd1:    pal_rgb = pal_drk;
            3'd2:    pal_rgb = pal_hil;
            3'd3:    pal_rgb = 24'hFFFFFF;
            3'd4:    pal_rgb = 24'h141A20;
            3'd5:    pal_rgb = 24'h54606C;
            3'd6:    pal_rgb = 24'h28323C;
            3'd7:    pal_rgb = 24'h000000;
            default: pal_rgb = 24'h000000;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            osd_on <= 1'b0; osd_rgb <= 24'd0;
        end else begin
            if (de && ra_en && num_win && bits[15 - font_col]) begin
                osd_on  <= 1'b1; osd_rgb <= 24'hFFFFFF;   // 倒车距离数字：白
            end else if (de && (osel == 2'd0)) begin
                // 倒车辅助图形：颜色由上游调色板索引决定
                osd_on  <= 1'b1;
                osd_rgb <= pal_rgb;
            end else if (de && (osel == 2'd1) && (y >= Y0) && (y < Y0 + 11'd16) &&
                         (x >= X0) && (cpos < NCHAR) && bits[15 - col]) begin
                osd_on  <= 1'b1; osd_rgb <= 24'hFFFFFF;      // 白色字幕
            end else if (de && (osel == 2'd2) && bar_fg) begin
                osd_on  <= 1'b1; osd_rgb <= 24'h00FFA0;      // 实时电平：亮青绿
            end else if (de && (osel == 2'd2) && bar_bg) begin
                osd_on  <= 1'b1; osd_rgb <= 24'h101820;      // 底框：近黑
            end else begin
                osd_on  <= 1'b0; osd_rgb <= 24'd0;
            end
        end
    end
endmodule
