`timescale 1ns / 1ps
// ============================================================================
// voice_rom.v —— 倒车语音播报样本 ROM（只读）
//
// 4 段真人中文语音（16kHz / 8bit / 单声道，裁剪静音 + 抗混叠重采样 + 峰值归一化后）：
//   seg0 (200cm): "安全"   起始 0x00000  长度 9091
//   seg1 (120cm): "注意"   起始 0x02383  长度 7866
//   seg2 (60cm):  "小心"   起始 0x0423D  长度 9130
//   seg3 (20cm):  "危险"   起始 0x065E7  长度 9524
//
// 布局：紧凑排列（无对齐填充）。总深度 35611，16bit 地址。
// 8bit 样本按"有符号"存储（-128..127），上层播放时左移补成 24bit。
// ============================================================================
module voice_rom (
    input  wire        clk,
    input  wire [15:0] addr,       // 16bit 地址，覆盖 0..0x8B1A
    output reg  [7:0]  dout        // 8bit 有符号样本
);

    // 推断式 BRAM：TD 会映射到 EMB
    reg [7:0] mem [0:35610];  /* fehdl force_ram=1, ram_style="bram" */

    initial begin
        $readmemh("voice_rom.hex", mem);
    end

    // 同步读（BRAM 读时序：地址当拍，数据下一拍）
    always @(posedge clk) begin
        dout <= mem[addr];
    end

endmodule
