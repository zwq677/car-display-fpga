`timescale 1ns / 1ps
// 音视频联动提示音：图像切换时输出一段 ~1kHz 方波（经板载 PWM 低通/功放输出）
module audio_beep #(
    parameter TONE_DIV = 16'd49999,      // 100MHz / 50000 = 2kHz 周期 -> 1kHz 音调
    parameter BEEP_LEN = 23'd8388607     // ~84ms @100MHz
)(
    input  wire clk,        // 100MHz (sd_card_clk)
    input  wire rst,
    input  wire trig,       // 切换事件脉冲
    output wire pwm_out,    // 音频 PWM 输出
    output reg  [4:0] lvl    // 音频电平包络(0..31)
);
    reg [22:0] beep_timer;
    reg [15:0] tone_cnt;
    reg [24:0] period_cnt;   // 周期提示音计数
    wire       period_trig = (period_cnt >= 25'd150_000_000);   // ~1.5s @100MHz

    always @(posedge clk or posedge rst) begin
        if (rst)                          period_cnt <= 25'd0;
        else if (period_trig)             period_cnt <= 25'd0;
        else                              period_cnt <= period_cnt + 1'b1;
    end

    always @(posedge clk or posedge rst) begin
        if (rst)                          beep_timer <= 23'd0;
        else if (trig | period_trig)      beep_timer <= BEEP_LEN;
        else if (beep_timer != 0) beep_timer <= beep_timer - 1'b1;
    end

    always @(posedge clk or posedge rst) begin
        if (rst)                        tone_cnt <= 16'd0;
        else if (tone_cnt >= TONE_DIV)  tone_cnt <= 16'd0;
        else                            tone_cnt <= tone_cnt + 1'b1;
    end

    assign pwm_out = (beep_timer != 0) && (tone_cnt < (TONE_DIV >> 1));

    // 电平包络：beep 期间在 0..31 之间变化
    always @(posedge clk or posedge rst) begin
        if (rst) lvl <= 5'd0;
        else if (beep_timer != 0) lvl <= beep_timer[21:17];
        else lvl <= 5'd0;
    end
endmodule
