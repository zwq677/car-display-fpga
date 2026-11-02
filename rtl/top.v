`timescale 1ns / 1ps
// ============================================================
// 选题一 大拇指板适配版（纯视频链路，无音频/无 EDID）
// SD/TF 卡 FAT32 扫描读 BMP -> SDRAM 双缓冲 -> HDMI 显示
// 复用官方 lab_ex5_i2s 的 SD/帧缓存/时序，HDMI 换成大拇指板 hdmi_tx
// ============================================================
module top(
    input           clk,          // 50MHz 系统时钟
    input           rst_n,        // 低有效复位（SW0）
    input           key1,         // 手动下一张（SW1）
    input           key2,         // 自动播放开关（SW2）

    // TF/SD 卡 SPI
    output          sd_ncs,       // 片选（低有效）
    output          sd_dclk,      // SPI 时钟
    output          sd_mosi,      // FPGA->SD
    input           sd_miso,      // SD->FPGA

    // HDMI TMDS
    output          HDMI_CLK_P,
    output          HDMI_D2_P,
    output          HDMI_D1_P,
    output          HDMI_D0_P,

    // 调试指示灯（大拇指板 8 个 LED，高电平点亮）
    output [7:0]    led,

    // 参数调节拨码开关（2 位全部归还给原有 4 档亮度，语义与原始工程完全一致）
    //   param[1:0] : 亮度档位 4 档（00/01/10/11 -> 20/70/120/170 增益）
    //   倒车辅助模式改由【按键 SW1 长按 1.2s】切换，不再占用拨码。
    input  wire [1:0] param
);

parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter FRAME_PIXELS  = 24'd307200;   // 640*480
parameter BUF0_ADDR     = 24'd0;
parameter BUF1_ADDR     = FRAME_PIXELS;

// ---- 上电复位 + SD 读卡失败自动重试 ----
reg [7:0] rst_cnt;
reg       retry_rst;          // 读卡失败时的重试复位脉冲
always @(posedge clk) begin
    if (!rst_n || retry_rst) rst_cnt <= 8'd0;
    else if (!rst_cnt[7])    rst_cnt <= rst_cnt + 1'b1;
end
wire sys_rst_n = rst_cnt[7] & rst_n;
wire rst_all   = ~sys_rst_n;
wire beep_en;
wire       Sdr_init_done;
wire [3:0] state_code;
wire [2:0] dbg_img_count;   // 调试观测：扫描到的合格图片张数

// ---- 静音控制（SW2 长按 1.2s 翻转）----
// 见下方 clk 域按键处理段：k2_hl 也在 clk 域累加。

// ============================================================================
// SD 卡重试复位（只认"SD 卡未初始化"这一种确定死锁，不再按 state_code==2 超时）
// ----------------------------------------------------------------------------
// 【为什么去掉 state_code==2 超时】
//   state_code==2 在 bmp_read.v 里同时表示"扫描中 ST_SCAN"和"加载图片头 ST_LOAD_HDR"
//   两个阶段，且正常显示图片、切换图片时都会反复进出 2。用它做 35s 超时，
//   会在"正常读图"时误触发 retry_rst，把 sd_card_bmp（其按键消抖用 sd_card_clk
//   且复位接 rst_all）整体复位 —— 表现为"切图失效、倒车正常"（倒车按键在 clk 域，
//   永不复位，故不受影响）。这是之前为修"必须断电死锁"引入的副作用。
// 【当前对策】
//   只保留原工程的"SD 未初始化(state_code==0)持续 5s 才重试"。读扇区阶段卡死
//   的死锁是原厂 sd_card_cmd.v S_READ_WAIT 无超时导致的，不在本层强行兜底，
//   避免误伤正常读图。真要修读扇区卡死，应去 sd_card_cmd.v 补超时，而非复位整机。
// ============================================================================

// 若 SDRAM 已就绪但 SD 卡长时间(~5s) 未初始化，则周期性复位重试
reg [27:0] retry_cnt;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        retry_cnt <= 28'd0; retry_rst <= 1'b0;
    end else begin
        retry_rst <= 1'b0;
        if (Sdr_init_done && (state_code == 4'd0)) begin
            if (retry_cnt >= 28'd250_000_000) begin
                retry_cnt <= 28'd0;
                retry_rst <= 1'b1;
            end else
                retry_cnt <= retry_cnt + 1'b1;
        end else
            retry_cnt <= 28'd0;
    end
end

// ---- 时钟（复用官方 PLL） ----
wire sd_card_clk, ext_mem_clk, ext_mem_clk_sft, video_clk, hdmi_5x_clk;
sys_pll sys_pll_m0(
    .refclk(clk), .clk0_out(sd_card_clk), .clk1_out(ext_mem_clk), .clk2_out(ext_mem_clk_sft), .reset(1'b0)
);
video_pll video_pll_m0(
    .refclk(clk), .clk0_out(video_clk), .clk1_out(hdmi_5x_clk), .reset(1'b0)
);

// ---- SD BMP + 帧缓存信号 ----
wire Sdr_init_ref_vld, Sdr_busy;
wire [1:0] write_buf_idx, disp_buf_idx;
wire sd_card_write_req, sd_card_write_req_ack, sd_card_write_en, frame_write_finish;
wire [31:0] sd_card_write_data;
wire display_valid;
reg  frame_write_toggle_mem;

wire App_rd_en, App_wr_en, Sdr_rd_en;
wire [ADDR_BITS-1:0]     App_rd_addr, App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din, Sdr_rd_dout;
wire [3:0]               App_wr_dm;

// mem_clk 域把 write_finish 转 toggle，供 sd_card_clk 域同步
always @(posedge ext_mem_clk or posedge rst_all) begin
    if (rst_all)              frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish) frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

// ---- TF 多图扫描与缓存（双缓冲） ----
sd_card_bmp #(
    .CLK_FREQ_HZ(100_000_000),
    .SCAN_START_SECTOR(32'd0),
    .SCAN_MAX_SECTOR(32'd131071),
    .SCAN_TARGET_COUNT(3'd4)
) sd_card_bmp_m0(
    .clk(sd_card_clk), .rst(rst_all), .key_next(key1), .key_auto(key2),
    .state_code(state_code), .img_count(dbg_img_count), .bmp_width(16'd640), .bmp_height(16'd480), .display_valid(display_valid),
    .write_finish_toggle(frame_write_toggle_mem), .write_buf_idx(write_buf_idx), .disp_buf_idx(disp_buf_idx),
    .write_req(sd_card_write_req), .write_req_ack(sd_card_write_req_ack),
    .write_en(sd_card_write_en), .write_data(sd_card_write_data),
    .SD_nCS(sd_ncs), .SD_DCLK(sd_dclk), .SD_MOSI(sd_mosi), .SD_MISO(sd_miso)
);

// ---- 视频时序 ----
wire hs_0, vs_0, de_0, hs, vs, de;
wire video_read_req, video_read_req_ack, video_read_en;
wire [31:0] video_read_data;
wire [23:0] vout_data_raw, vout_data;

video_timing_data video_timing_data_m0(
    .video_clk(video_clk), .rst(rst_all), .read_req(video_read_req), .read_req_ack(video_read_req_ack),
    .hs(hs_0), .vs(vs_0), .de(de_0)
);

video_delay video_delay_m0(
    .video_clk(video_clk), .rst(rst_all), .read_en(video_read_en), .read_data(video_read_data[31:8]),
    .hs(hs_0), .vs(vs_0), .de(de_0), .hs_r(hs), .vs_r(vs), .de_r(de), .vout_data(vout_data_raw)
);

// 首图提交前黑屏，提交后一直显示当前缓冲区
assign vout_data = display_valid ? vout_data_raw : 24'd0;

frame_read_write #(
    .WRITE_V_FLIP(1), .FRAME_WIDTH(640), .FRAME_HEIGHT(480)
) frame_read_write_m0(
    .mem_clk(ext_mem_clk), .rst(rst_all),
    .Sdr_init_done(Sdr_init_done), .Sdr_init_ref_vld(Sdr_init_ref_vld), .Sdr_busy(Sdr_busy),
    .App_rd_en(App_rd_en), .App_rd_addr(App_rd_addr), .Sdr_rd_en(Sdr_rd_en), .Sdr_rd_dout(Sdr_rd_dout),
    .read_clk(video_clk), .read_req(video_read_req), .read_req_ack(video_read_req_ack), .read_finish(),
    .read_addr_0(BUF0_ADDR), .read_addr_1(BUF1_ADDR), .read_addr_2(24'd0), .read_addr_3(24'd0),
    .read_addr_index(disp_buf_idx), .read_len(FRAME_PIXELS),
    .read_en(video_read_en), .read_data(video_read_data),
    .App_wr_en(App_wr_en), .App_wr_addr(App_wr_addr), .App_wr_din(App_wr_din), .App_wr_dm(App_wr_dm),
    .write_clk(sd_card_clk), .write_req(sd_card_write_req), .write_req_ack(sd_card_write_req_ack),
    .write_finish(frame_write_finish),
    .write_addr_0(BUF0_ADDR), .write_addr_1(BUF1_ADDR), .write_addr_2(24'd0), .write_addr_3(24'd0),
    .write_addr_index(write_buf_idx), .write_len(FRAME_PIXELS),
    .write_en(sd_card_write_en), .write_data(sd_card_write_data)
);

// ---- SDRAM 控制器 ----
sdram U3(
    .Clk(ext_mem_clk), .Clk_sft(ext_mem_clk_sft), .Rst(rst_all),
    .Sdr_init_done(Sdr_init_done), .Sdr_init_ref_vld(Sdr_init_ref_vld), .Sdr_busy(Sdr_busy),
    .App_wr_en(App_wr_en), .App_wr_addr(App_wr_addr), .App_wr_dm(App_wr_dm), .App_wr_din(App_wr_din),
    .App_rd_en(App_rd_en), .App_rd_addr(App_rd_addr), .Sdr_rd_en(Sdr_rd_en), .Sdr_rd_dout(Sdr_rd_dout)
);



// ---- 转场特效：切图淡入（扩展项②，安全版） ----
// 把 disp_buf_idx 用两级同步器同步到像素时钟域，检测变化后触发淡入
reg [1:0] dbi_s0, dbi_s1;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin dbi_s0 <= 2'd0; dbi_s1 <= 2'd0; end
    else begin dbi_s0 <= disp_buf_idx; dbi_s1 <= dbi_s0; end
end
wire buf_chg = (dbi_s0 != dbi_s1);

// 亮度 0->255 慢速渐变（约 0.4s @25MHz），且始终保证会升到 255
reg [7:0]  bright;
reg [15:0] fade_wait;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        bright <= 8'd255; fade_wait <= 16'd0;
    end else if (buf_chg) begin
        bright <= 8'd0; fade_wait <= 16'd0;
    end else if (bright != 8'd255) begin
        if (fade_wait == 16'd20000) begin
            fade_wait <= 16'd0; bright <= bright + 1'b1;
        end else begin
            fade_wait <= fade_wait + 16'd1;
        end
    end
end


// ---- 实时参数调节（亮度）：拨码开关 param[1:0] 选 4 档（与原工程一致）----
wire [7:0] user_gain = (param == 2'b00) ? 8'd20  :
                       (param == 2'b01) ? 8'd70  :
                       (param == 2'b10) ? 8'd120 : 8'd170;
wire [15:0] gain16 = bright * user_gain;
wire [7:0]  gain   = gain16[15:8];

wire [15:0] fr = vout_data[23:16] * gain;
wire [15:0] fg = vout_data[15:8]  * gain;
wire [15:0] fb = vout_data[7:0]   * gain;
wire [23:0] img_faded = {fr[15:8], fg[15:8], fb[15:8]};

// ---- OSD 字幕叠加 ----
// 从最终 de 重建像素坐标（与 vout_data 对齐）
reg [11:0] osd_x;
reg [10:0] osd_y;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        osd_x <= 12'd0; osd_y <= 11'd0;
    end else if (de) begin
        if (osd_x == 12'd639) begin
            osd_x <= 12'd0;
            if (osd_y == 11'd479) osd_y <= 11'd0;
            else                   osd_y <= osd_y + 1'b1;
        end else osd_x <= osd_x + 1'b1;
    end
end

wire        osd_on;
wire [23:0] osd_rgb;
// 注：osd_overlay 实例化移到下方音频段之后 —— 它要接 audio_level_meter
//     的电平输出，而该电平依赖 audio_left_g，必须后置声明。

// ---- 音频：内部 I2S 测试音（走 HDMI 内嵌音频） ----
// audio_pll_lock 仅作锁定观测，不并入系统复位（并入会让 HDMI 核长期复位而黑屏）
wire        audio_pll_lock;
wire        audio_mclk;
PLL_HDMI_AUDIO u_audio_pll(
    .refclk(clk), .reset(1'b0), .extlock(audio_pll_lock),
    .clk0_out(), .clk1_out(), .clk2_out(audio_mclk)
);
wire        audio_i2s_bclk, audio_i2s_lrck, audio_i2s_dout;
wire        audio_valid;
wire [23:0] audio_left_data, audio_right_data;
wire        acr_valid;
wire [19:0] acr_cts, acr_n;

// 倒车语音播报：根据距离档 ra_dist 播放对应真人语音（替换原正弦乐音盒）
voice_player u_tone (
    .I_mclk(audio_mclk), .I_rst(rst_all),
    .I_dist(ra_dist), .I_voice_en(ra_en),
    .O_i2s_BCLK(audio_i2s_bclk), .O_i2s_LRCK(audio_i2s_lrck), .O_i2s_DOUT(audio_i2s_dout)
);
I2S_receiver u_i2s_rx (
    .I_clk(video_clk), .I_rst(rst_all),
    .I_i2s_BCLK(audio_i2s_bclk), .I_i2s_LRCK(audio_i2s_lrck), .I_i2s_DOUT(audio_i2s_dout),
    .O_audio_valid(audio_valid), .O_audio_left_data(audio_left_data), .O_audio_right_data(audio_right_data)
);
// ---- 提示音门控：上电 + 切图时响约 0.25 秒，其余时间静音 ----
// 倒车辅助开启时，提示音改由"距离档"驱动，分级节奏见下方 ra_gap

// ---- 倒车辅助模式（与 osd_overlay 的 osel 通道选择同源）----
// 声明前置：本工程历史上两次隐性 bug 都是"先用后声明"导致 1 位隐式线网
// （见 工作报告 2.3 缺陷 2 / 缺陷 3），这里所有相关线网一律在首次使用前声明。
wire       ra_en;                   // 倒车模式寄存器（SW1 长按翻转），见下方按键处理段

reg [1:0]  disp_idx_v1, disp_idx_v2, disp_idx_v3;
reg [21:0] beep_timer;

wire [1:0] ra_lvl;                   // 倒车预警分级
wire       ra_beep_hi;               // 倒车分级「响」半周期（由 reverse_assist 节拍器给出）

reg        ra_bee_r;                 // 倒车模式提示音节拍（1 = 响）

// 提示音相关全部改到 clk（50MHz）域：
// video_clk 域每多一级 22 位计数/比较，sd_card_clk 域的布局就被挤薄一次
// （实测 mslices 从 470 涨到 754，sd_card_clk SWNS 从 +0.7 掉到 +0.18）。
// 25MHz 的计数器直接搬到 50MHz，阈值翻倍即可，功能完全等价。
// 提示音对 20ms 级别的抖动毫无感知，跨一个使能信号是安全的。
localparam [21:0] BEEP_ON_CYC  = 22'd3_000_000;    // 60ms  @ 50MHz
localparam [21:0] BEEP_CHG_CYC = 22'd12_500_000;   // 250ms @ 50MHz（上电/切图提示音）

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        disp_idx_v1 <= 2'd0; disp_idx_v2 <= 2'd0; disp_idx_v3 <= 2'd0;
        beep_timer  <= BEEP_CHG_CYC;
        ra_bee_r    <= 1'b0;
    end else begin
        disp_idx_v1 <= disp_buf_idx;
        disp_idx_v2 <= disp_idx_v1;
        disp_idx_v3 <= disp_idx_v2;
        if (disp_idx_v2 != disp_idx_v3) begin
            beep_timer <= BEEP_CHG_CYC;            // 切图提示音约 0.25s
        end else if (beep_timer != 22'd0) begin
            beep_timer <= beep_timer - 1'b1;
        end

        // 倒车分级提示音：安全=静音 / 注意=慢 / 警告=较快 / 危险=快速
        // 响/停 由 reverse_assist 的视频域节拍器统一产生（含 0.5s 上电静默），
        // 这里只做跨域同步，不承担任何计数，避免占用 video_clk 布局。
        if (!ra_en) begin
            ra_bee_r <= 1'b0;
        end else begin
            ra_bee_r <= ra_beep_hi;        // 1 = 处于「响」半周期
        end
    end
end

// 倒车模式：语音由 voice_player 连续播报（内部已按档位选段+静音间隔），
//   这里只做静音总闸门（mute），不再用 ra_bee_r 做响/停节拍。
// 非倒车模式：保留原"上电/切图提示音"（beep_timer）。
assign      beep_en      = ra_en ? (~mute) : ((beep_timer != 22'd0) & ~mute);
wire [23:0] audio_left_g  = beep_en ? audio_left_data  : 24'sd0;
wire [23:0] audio_right_g = beep_en ? audio_right_data : 24'sd0;

audio_arc_calculate #(.ACR_N(6144)) u_arc (
    .I_clk(video_clk), .I_rst(rst_all), .I_audio_valid(audio_valid),
    .O_acr_valid(acr_valid), .O_acr_cts(acr_cts), .O_acr_n(acr_n)
);

// ---- 音频可视化（扩展项⑤）：真实 PCM 电平 -> OSD 柱条 ----
// 只新增一个电平计，绘制复用 osd_overlay 的输出寄存器，
// 不额外占用像素合成通路（本工程布局余量极小，多一条 24bit mux
// 就会挤掉 sd_card_clk 域扫描逻辑的布局空间）。
wire [4:0] audio_lvl;
audio_level_meter u_lvl (
    .clk(video_clk), .rst(rst_all),
    .audio_valid(audio_valid),
    .audio_l(audio_left_g), .audio_r(audio_right_g),
    .level(audio_lvl)
);

// ============================================================================
// 创新功能：倒车辅助与障碍物预警（reverse_assist）
// ----------------------------------------------------------------------------
// 资源分配依据（README_接续说明.md 第 6/10 节 + 交接包 pin.adc + 两份 docx）：
//
//   拨码 SW3  param[0]  A11 —— 原亮度 4 档最低位。保留，亮度变 2 档（20/170）。
//   按键 SW1  key1      A10 —— 原"短按切图 / 长按静音"。
//                              【长按 1.2s = 开/关倒车辅助模式】（原倒车用拨码，已改）
//                              【短按 = 倒车模式下切距离档】；非倒车模式保持原"下一张"
//   按键 SW2  key2      B10 —— 原"自动轮播开关"，完整保留；
//                              倒车模式下兼作【距离档回 200cm】
//   拨码 SW3/SW4 param[1:0] —— 全部归还给原有 4 档亮度（20/70/120/170）
//   LED[7:0]  B14..F16      —— 8 根全部被 SD 状态码/HDMI 锁定/SDRAM/写请求/
//                              静音占用。倒车档位与分级改由画面颜色+文字指示，
//                              不动 LED 分配，避免破坏原有调试信息。
//   蜂鸣器                  —— 交接包 pin.adc 与两份 docx 均未定义蜂鸣器管脚。
//                              大拇指标准板的 BUZZER(H11) 在本板约束中不存在，
//                              无法确认硬件可用，因此【不驱动实体蜂鸣器】，
//                              改用 HDMI 内嵌音频输出分级提示音（见上方 ra_gap）。
//
// 时钟域：全部逻辑在 video_clk（25.175MHz）域，不触碰 sd_card_clk 域。
// ============================================================================

// ---- 20ms 消抖 + 单脉冲 ----
// 【重要】按键处理放在 clk（50MHz 晶振直供）域，不放 video_clk 域。
// 原因：video_clk 由 PLL 产生，且 rst_all 中含 retry_rst —— SD 卡读失败时会
// 周期性复位整个视频域。按键状态机若在视频域，会被这些复位反复打断，
// 长按计数与边沿检测全部失效，表现就是"按键完全没反应、档位永远不变"。
// clk 是晶振直供、永不复位，消抖和长按在这里做最稳。
// 50MHz：20ms = 1,000,000 拍；1.2s = 60,000,000 拍
localparam [20:0] RA_DB_CYC  = 21'd1_000_000;
localparam [26:0] RA_HL_CYC  = 27'd60_000_000;

reg        p2_dbn;                   // 倒车模式寄存器（SW1 长按 1.2s 翻转）
reg        k1_s0, k1_s1, k1_dbn;     // SW1 消抖链
reg [20:0] k1_cnt;
reg [26:0] k1_hl;                    // SW1 长按计数
reg        k2_s0, k2_s1, k2_dbn;     // SW2 消抖链
reg [20:0] k2_cnt;
reg [26:0] k2_hl;                    // SW2 长按计数（静音）
reg        k1_dbn_d, k2_dbn_d;
reg        k2_hl_d;
reg        mute;
reg        ra_step_p, ra_rst_p;
reg        ra_ini_p;

// 跨域 toggle 寄存器：clk 域每次事件翻转一次，video_clk 域检测其变化沿
reg  ra_step_tgl, ra_rst_tgl, ra_ini_tgl;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        p2_dbn    <= 1'b0;
        k1_s0     <= 1'b1; k1_s1 <= 1'b1; k1_dbn <= 1'b1; k1_cnt <= 21'd0;
        k1_hl     <= 27'd0;
        k2_s0     <= 1'b1; k2_s1 <= 1'b1; k2_dbn <= 1'b1; k2_cnt <= 21'd0;
        k2_hl     <= 27'd0;
        k1_dbn_d  <= 1'b1; k2_dbn_d <= 1'b1;
        k2_hl_d   <= 1'b0; mute <= 1'b0;
        ra_step_p <= 1'b0; ra_rst_p <= 1'b0; ra_ini_p <= 1'b0;
        ra_step_tgl <= 1'b0; ra_rst_tgl <= 1'b0; ra_ini_tgl <= 1'b0;
    end else begin
        // 同步器 + 20ms 消抖（按键低有效：0 = 按下，1 = 松开）
        k1_s0 <= key1;       k1_s1 <= k1_s0;
        k2_s0 <= key2;       k2_s1 <= k2_s0;

        if (k1_s1 == k1_dbn) k1_cnt <= 21'd0;
        else if (k1_cnt >= RA_DB_CYC) begin k1_dbn <= k1_s1; k1_cnt <= 21'd0; end
        else                  k1_cnt <= k1_cnt + 1'b1;

        if (k2_s1 == k2_dbn) k2_cnt <= 21'd0;
        else if (k2_cnt >= RA_DB_CYC) begin k2_dbn <= k2_s1; k2_cnt <= 21'd0; end
        else                  k2_cnt <= k2_cnt + 1'b1;

        // 打一拍用于边沿检测
        k1_dbn_d <= k1_dbn;
        k2_dbn_d <= k2_dbn;

        // 长按计数：按下期间累加；达到 1.2s 时翻转 p2_dbn 并给 ra_ini_p 一个脉冲。
        if (k1_dbn == 1'b0) begin
            if (k1_hl < RA_HL_CYC) k1_hl <= k1_hl + 1'b1;
        end else begin
            k1_hl <= 27'd0;
        end

        if (k2_dbn == 1'b0) begin
            if (k2_hl < RA_HL_CYC) k2_hl <= k2_hl + 1'b1;
        end else begin
            k2_hl <= 27'd0;
        end

        // SW1 长按达成的那一拍：翻转倒车模式 + 让档位回 200
        if (k1_hl == RA_HL_CYC - 27'd1) begin
            p2_dbn   <= ~p2_dbn;
            ra_ini_p <= 1'b1;
        end else begin
            ra_ini_p <= 1'b0;
        end

        // SW2 长按达成的那一拍：翻转静音
        k2_hl_d <= (k2_hl == RA_HL_CYC - 27'd1);
        if ((k2_hl == RA_HL_CYC - 27'd1) & ~k2_hl_d) mute <= ~mute;

        ra_step_p <= k1_dbn_d & ~k1_dbn;
        ra_rst_p  <= k2_dbn_d & ~k2_dbn;

        // ---- 跨域：用"翻转"而不是"电平/脉冲"----
        // 每次事件把 clk 域的 toggle 寄存器翻一下，video_clk 域打两拍同步后
        // 检测它的变化沿。好处：无论两域相位如何、周期比如何，
        // 一次事件在 video_clk 域只会被认出一次，绝不会重复触发或漏掉。
        if (ra_step_p) ra_step_tgl <= ~ra_step_tgl;
        if (ra_rst_p)  ra_rst_tgl  <= ~ra_rst_tgl;
        if (ra_ini_p)  ra_ini_tgl  <= ~ra_ini_tgl;
    end
end

// video_clk 域：两级同步 + 边沿检测，产生单拍脉冲
reg [1:0] st_sync, rs_sync, in_sync;
reg       st_d, rs_d, in_d;
reg       k1_st_v, k2_st_v, ki_v;

always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        st_sync <= 2'b0; rs_sync <= 2'b0; in_sync <= 2'b0;
        st_d <= 1'b0; rs_d <= 1'b0; in_d <= 1'b0;
        k1_st_v <= 1'b0; k2_st_v <= 1'b0; ki_v <= 1'b0;
    end else begin
        st_sync <= {st_sync[0], ra_step_tgl};
        rs_sync <= {rs_sync[0], ra_rst_tgl};
        in_sync <= {in_sync[0], ra_ini_tgl};
        st_d <= st_sync[1];  rs_d <= rs_sync[1];  in_d <= in_sync[1];
        // 单拍脉冲
        k1_st_v <= st_sync[1] ^ st_d;
        k2_st_v <= rs_sync[1] ^ rs_d;
        ki_v    <= in_sync[1] ^ in_d;
    end
end

wire        ra_hit;
wire [2:0]  ra_idx;
wire [1:0]  ra_dist;

assign ra_en = p2_dbn;              // 倒车模式寄存器（SW1 长按 1.2s 翻转）

reverse_assist u_ra (
    .clk       (video_clk),
    .rst_n     (~rst_all),
    .de        (de),
    .x         (osd_x),
    .y         (osd_y),
    .en        (ra_en),
    .key_step  (k1_st_v),
    .key_rst   (k2_st_v),
    .key_ini   (ki_v),
    .hit       (ra_hit),
    .idx       (ra_idx),
    .lvl       (ra_lvl),
    .dist_sel  (ra_dist),
    .beep_hi   (ra_beep_hi)
);

// 通道选择优先级（纯组合、不打拍 -> 不增加像素延迟）
//   倒车图形 > 字幕 > 音频柱条 > 无
wire [1:0] osd_osel = ra_hit                                    ? 2'd0 :
                      (osd_y >= 11'd446)                        ? 2'd1 :
                      ((osd_y >= 11'd420) && (osd_y < 11'd438) &&
                       (osd_x >= 12'd480) && (osd_x < 12'd632)) ? 2'd2 :
                                                                  2'd3 ;

// 调试观测：图片张数从 sd_card_clk 域跨到 video_clk 域，两级同步（值秒级稳定，仅用于显示）
reg [2:0] dbg_cnt_s0, dbg_cnt_s1;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        dbg_cnt_s0 <= 3'd0; dbg_cnt_s1 <= 3'd0;
    end else begin
        dbg_cnt_s0 <= dbg_img_count;
        dbg_cnt_s1 <= dbg_cnt_s0;
    end
end

osd_overlay u_osd(
    .clk(video_clk), .rst_n(~rst_all), .de(de), .x(osd_x), .y(osd_y),
    .dbg_code(state_code), .dbg_code2({3'b0, param[0]}), .dbg_cnt(dbg_cnt_s1),
    .audio_lvl(audio_lvl),
    .osel(osd_osel), .pal_sel(ra_idx), .lvl(ra_lvl), .dist_sel(ra_dist),
    .ra_en(ra_en),
    .osd_on(osd_on), .osd_rgb(osd_rgb)
);

// 叠加：字幕/电平条像素覆盖图像像素
wire [23:0] pixel_out = osd_on ? osd_rgb : img_faded;

// ---- RGB/DE 转 AXIS 视频 ----
wire        axis_s_user, axis_s_valid, axis_s_last;
wire [23:0] axis_s_data;
video_rgb_to_axis_640x480 u_rgb2axis (
    .I_clk(video_clk), .I_rst(rst_all), .I_vs(vs), .I_de(de), .I_rgb(pixel_out),
    .O_video_user(axis_s_user), .O_video_valid(axis_s_valid), .O_video_last(axis_s_last), .O_video_data(axis_s_data)
);

// ---- EDID 触发 ----
wire edid_trig, edid_valid;
wire [7:0] edid_data;
startup_pulse #(.CNT_MAX(20'd100000)) u_edid (
    .I_clk(video_clk), .I_rst(rst_all), .O_pulse(edid_trig)
);

// ---- HDMI 1.4b 发送核 + PHY ----
wire [9:0] tmds_ch0, tmds_ch1, tmds_ch2, tmds_clk;
wire       hdmi_video_locked;
wire       ddc_scl; wire ddc_sda;
assign ddc_sda = 1'bz;
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE("EG"), .HTOTAL(800), .HSA(96), .HFP(16), .HBP(48), .HACTIVE(640),
    .VTOTAL(525), .VSA(2), .VFP(10), .VBP(33), .VACTIVE(480),
    .VIDEO_VIC(1), .VIDEO_TPG("Disable"), .VIDEO_FORMAT("RGB"),
    .AUDIO_SAMPLE_RATE("48K"), .IIC_SCL_DIV(250)
) u_hdmi_core (
    .I_pixel_clk(video_clk), .I_rst(rst_all),
    .I_edid_read_trig(edid_trig), .O_edid_read_valid(edid_valid), .O_edid_read_data(edid_data),
    .I_axis_s_user(axis_s_user), .I_axis_s_valid(axis_s_valid), .I_axis_s_last(axis_s_last),
    .I_axis_s_data(axis_s_data), .O_axis_s_ready(),
    .I_audio_valid(audio_valid), .I_audio_left_data(audio_left_g), .I_audio_right_data(audio_right_g),
    .I_acr_valid(acr_valid), .I_acr_cts(acr_cts), .I_acr_n(acr_n),
    .O_video_locked(hdmi_video_locked), .O_ddc_scl(ddc_scl), .IO_ddc_sda(ddc_sda),
    .O_ch0_tmds_data(tmds_ch0), .O_ch1_tmds_data(tmds_ch1), .O_ch2_tmds_data(tmds_ch2), .O_clk_tmds_data(tmds_clk)
);
hdmi_phy_wrapper #(.DEVICE("EG")) u_phy (
    .I_pixel_clk(video_clk), .I_serial_clk(hdmi_5x_clk), .I_rst(rst_all),
    .I_tmds_channel_0(tmds_ch0), .I_tmds_channel_1(tmds_ch1), .I_tmds_channel_2(tmds_ch2), .I_tmds_channel_clk(tmds_clk),
    .O_tmds_ch0_p(HDMI_D0_P), .O_tmds_ch1_p(HDMI_D1_P), .O_tmds_ch2_p(HDMI_D2_P), .O_tmds_clk_p(HDMI_CLK_P)
);


// ---- 调试指示灯 ----
// led[3:0] = SD 卡状态码；led[4]=读到图；led[5]=SDRAM就绪；led[6]=写请求；led[7]=帧写活动
assign led[3:0] = state_code;
assign led[4]   = hdmi_video_locked;
assign led[5]   = Sdr_init_done;
assign led[6]   = sd_card_write_req;
assign led[7]   = mute;

endmodule
