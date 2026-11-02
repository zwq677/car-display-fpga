`timescale 1ns / 1ps
// ============================================================
// 音频电平计（扩展项⑤ 的数据源，不含绘制）
// ------------------------------------------------------------
// 把实际播放的 24bit 有符号 PCM 换算成 0..31 的电平档，
// 交给 osd_overlay 复用现有字幕通路的输出寄存器画柱条。
// 这样不新增像素合成通路 —— 本工程在 TD6.2 下布局余量已接近 0，
// 任何独立的 24bit 输出 mux 或额外的加法器都会挤占 sd_card_clk 域
// 扫描逻辑的布局空间，实测会让 BMP 扫描漏检（只认到 1 张，不轮播）。
//
// 幅度映射：提示音 AMP=1,200,000，换算到样本高 8 位峰值约 18，
//           直接取高 5 位只有 2 档，柱条看不出变化。这里改为
//           "低 5 位 + 限幅"，18 直接落成 18 档（约 3/4 满格），
//           音量更大时由限幅兜住，不引入乘法/加法器。
// 数据来源：audio_left_g / audio_right_g（提示音门控后真正送 HDMI 的样本）。
// 时钟域：video_clk，audio_valid 为 48kHz 采样脉冲，同源无跨时钟域。
// ============================================================
module audio_level_meter #(
    parameter DEC_STEP = 10'd1500   // 回落步长：每 N 个采样电平降 1 档（约 1s 落到 0）
)(
    input  wire        clk,           // video_clk 25.175MHz
    input  wire        rst,           // 高有效复位
    input  wire        audio_valid,   // 48kHz 采样有效（单周期脉冲）
    input  wire signed [23:0] audio_l,
    input  wire signed [23:0] audio_r,

    output reg  [4:0]  level          // 实时电平 0..31
);

    // 只取样本高 8 位的绝对值（8bit 运算，比 24bit 省一个数量级）
    wire signed [7:0] s_l = audio_l[23:16];
    wire signed [7:0] s_r = audio_r[23:16];
    wire [8:0] a_l = s_l[7] ? (9'd0 - {1'b0, s_l}) : {1'b0, s_l};
    wire [8:0] a_r = s_r[7] ? (9'd0 - {1'b0, s_r}) : {1'b0, s_r};
    // 左右取较大者：本音源左右同相，取大值不丢信息且省一半逻辑
    wire [8:0] a_max = (a_l > a_r) ? a_l : a_r;
    // 直接当档位用（峰值约 18，落成 18 档），超过 31 档限幅
    wire [4:0] inst  = (a_max > 9'd31) ? 5'd31 : a_max[4:0];

    // 瞬时电平：快起慢落，保证无声时回到 0
    reg [9:0] dec_cnt;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            level   <= 5'd0;
            dec_cnt <= 10'd0;
        end else if (audio_valid) begin
            if (inst > level) level <= inst;
            else if (level != 5'd0 && dec_cnt >= DEC_STEP - 1'b1) level <= level - 1'b1;

            if (dec_cnt >= DEC_STEP - 1'b1) dec_cnt <= 10'd0;
            else                            dec_cnt <= dec_cnt + 1'b1;
        end
    end

endmodule
