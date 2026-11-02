`timescale 1ns / 1ps
// ============================================================================
// voice_player.v —— 倒车语音播报播放器（完整 I2S 发送 + voice_rom 读取）
//
// 替换原 hdmi_audio_tone_i2s_64fs（正弦乐音盒），改为播放真人语音：
//   倒车模式下，根据 dist_sel(距离档 0..3) 循环播报对应预警词：
//     0 -> "安全"   1 -> "注意"
//     2 -> "小心"   3 -> "危险"
//
// I2S 时序与原模块完全一致（64fs，BCLK = mclk/2 = 6.144MHz，LRCK = 96kHz）：
//   每个 LRCK 帧 = 左 32bit + 右 32bit，左右复用同一 24bit 样本。
//
// 重采样：voice_rom 样本 16kHz，播放帧率 96kHz，每个样本保持
//   HOLD = 96k/16k = 6 帧（精确整数分频，无音高偏移）。
//
// 段布局（紧凑排列，段内长度见 SEG_LEN）：
//   seg0 基址 0x00000 长 9091；seg1 0x02383 长 7866；
//   seg2 0x0423D 长 9130；seg3 0x065E7 长 9524。
// 播放到段末尾后，播一小段静音再从头循环（避免连续轰炸），
//   静音时长 = 0.5s @ 96kHz = 48000 帧。
// ============================================================================
module voice_player (
    input  wire        I_mclk,       // 12.288MHz 音频主时钟
    input  wire        I_rst,        // 高有效复位
    input  wire [1:0]  I_dist,       // 距离档 0..3（来自 reverse_assist 的 lvl/dist_sel）
    input  wire        I_voice_en,   // 倒车模式下使能播报（非倒车=0，静音）
    output reg         O_i2s_BCLK,
    output reg         O_i2s_LRCK,
    output reg         O_i2s_DOUT
);

    // ---- 段参数（与 voice_rom.hex 生成脚本保持一致）----
    localparam [15:0] SEG_BASE0 = 16'h00000;
    localparam [15:0] SEG_BASE1 = 16'h02383;
    localparam [15:0] SEG_BASE2 = 16'h0423D;
    localparam [15:0] SEG_BASE3 = 16'h065E7;
    localparam [15:0] SEG_LEN0  = 16'd9091;
    localparam [15:0] SEG_LEN1  = 16'd7866;
    localparam [15:0] SEG_LEN2  = 16'd9130;
    localparam [15:0] SEG_LEN3  = 16'd9524;

    // 每个 16kHz 样本在 96kHz 帧率下保持的帧数（96k/16k = 6 精确）
    localparam [3:0] HOLD = 4'd6;
    // 段播完后的静音帧数（0.5s @ 96kHz）
    localparam [15:0] GAP = 16'd48000;

    // ---- I2S 发送时序（复刻原模块）----
    reg [5:0]  S_bit_cnt;
    reg [63:0] S_shift_reg;
    reg [31:0] S_sample_word;   // 24bit 样本（低 24 位有效，高 8 位 0）

    // ---- voice_rom 读取 ----
    wire [7:0] rom_dout;
    reg  [15:0] rom_addr;
    reg  [15:0] seg_base;      // 当前段基地址
    reg  [15:0] seg_len;       // 当前段长度
    reg  [15:0] seg_off;       // 段内偏移（已读样本数）
    reg  [3:0]  hold_cnt;      // 6 分频
    reg  [15:0] gap_cnt;       // 段末静音计数
    reg         in_gap;        // 1 = 处于段末静音

    // ---- 跨时钟域同步：I_dist / I_voice_en 来自 video_clk / clk 域，慢信号，两级同步 ----
    reg [1:0] dist_s0, dist_s1;
    reg       ven_s0, ven_s1;
    always @(posedge I_mclk or posedge I_rst) begin
        if (I_rst) begin
            dist_s0 <= 2'd0; dist_s1 <= 2'd0;
            ven_s0  <= 1'b0; ven_s1  <= 1'b0;
        end else begin
            dist_s0 <= I_dist;
            dist_s1 <= dist_s0;
            ven_s0  <= I_voice_en;
            ven_s1  <= ven_s0;
        end
    end

    // 当前播放样本：静音期为中点 0x80，否则取 ROM 流水输出 rom_dout
    // （rom_dout 相对 rom_addr 固定延迟 1 拍，对所有样本一致，不影响音质）
    wire [7:0] w_cur_sample = in_gap ? 8'h80 : rom_dout;

    // 8bit 有符号 -> 24bit：左移 16 位（×65536），用纯位拼接实现（无组合移位器）
    //   s(-128..127) << 16 -> ±8,388,608，接近 24bit 满幅 ±8,388,607，音量最大化
    //   样本放 bit[23:16]，低 16 位补 0
    wire [23:0] w_sample_24 = { w_cur_sample, 16'd0 };

    // 段基地址 / 长度 查表（组合）
    always @(*) begin
        case (dist_s1)
            2'd0: begin seg_base = SEG_BASE0; seg_len = SEG_LEN0; end
            2'd1: begin seg_base = SEG_BASE1; seg_len = SEG_LEN1; end
            2'd2: begin seg_base = SEG_BASE2; seg_len = SEG_LEN2; end
            default: begin seg_base = SEG_BASE3; seg_len = SEG_LEN3; end
        endcase
    end

    voice_rom u_rom (
        .clk  (I_mclk),
        .addr (rom_addr),
        .dout (rom_dout)
    );

    always @(posedge I_mclk or posedge I_rst) begin
        if (I_rst) begin
            O_i2s_BCLK   <= 1'b0;
            O_i2s_LRCK   <= 1'b0;
            O_i2s_DOUT   <= 1'b0;
            S_bit_cnt    <= 6'd0;
            S_shift_reg  <= 64'd0;
            S_sample_word<= 32'd0;
            rom_addr     <= 16'd0;
            seg_off      <= 16'd0;
            hold_cnt     <= 4'd0;
            gap_cnt      <= 16'd0;
            in_gap       <= 1'b1;
        end else begin
            O_i2s_BCLK <= ~O_i2s_BCLK;

            if (O_i2s_BCLK == 1'b1) begin
                O_i2s_DOUT  <= S_shift_reg[63];
                S_shift_reg <= {S_shift_reg[62:0], 1'b0};

                if (S_bit_cnt == 6'd63) begin
                    S_bit_cnt <= 6'd0;

                    if (O_i2s_LRCK == 1'b0) begin
                        // 左声道发完 -> 右声道复用同一样本
                        O_i2s_LRCK  <= 1'b1;
                        S_shift_reg <= {S_sample_word[23:0], 40'd0};
                    end else begin
                        // 右声道发完 -> 下一帧：更新样本（96kHz 帧率）
                        O_i2s_LRCK  <= 1'b0;

                        // ---- 样本推进（6 分频 -> 16kHz）----
                        if (ven_s1) begin
                            if (in_gap) begin
                                // 静音期：计时结束后续播（从段首重新开始）
                                if (gap_cnt == GAP - 1) begin
                                    gap_cnt <= 16'd0;
                                    in_gap  <= 1'b0;
                                    seg_off <= 16'd0;
                                    hold_cnt<= 4'd0;
                                    rom_addr<= seg_base;
                                end else
                                    gap_cnt <= gap_cnt + 16'd1;
                            end else begin
                                // 播放期：每 8 帧推进一个样本地址
                                if (hold_cnt == HOLD - 1) begin
                                    hold_cnt <= 4'd0;
                                    if (seg_off == seg_len - 1) begin
                                        // 段结束 -> 进入静音间隔
                                        in_gap  <= 1'b1;
                                        gap_cnt <= 16'd0;
                                        seg_off <= 16'd0;
                                    end else begin
                                        seg_off  <= seg_off + 16'd1;
                                        rom_addr <= rom_addr + 16'd1;
                                    end
                                end else begin
                                    hold_cnt <= hold_cnt + 4'd1;
                                end
                            end
                        end else begin
                            // 非倒车模式：静音 + 复位播放指针
                            in_gap     <= 1'b1;
                            gap_cnt    <= 16'd0;
                            seg_off    <= 16'd0;
                            hold_cnt   <= 4'd0;
                            rom_addr   <= seg_base;
                        end

                        // 8bit 有符号 -> 24bit（经 w_sample_24 缩放）
                        S_sample_word <= {8'd0, w_sample_24};
                        S_shift_reg   <= {w_sample_24, 40'd0};
                    end
                end else begin
                    S_bit_cnt <= S_bit_cnt + 6'd1;
                end
            end
        end
    end

endmodule
