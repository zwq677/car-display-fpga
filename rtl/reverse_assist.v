`timescale 1ns / 1ps
// ============================================================================
// reverse_assist.v  ——  倒车辅助与障碍物预警（创新功能）
//
// 设计约束：
//   1. 全部逻辑在 video_clk（25.175MHz）域，不碰 sd_card_clk 域。
//   2. 不新增 24bit 像素 mux，绘制经 osd_overlay 复用同一组输出寄存器。
//   3. 组合逻辑刻意做到最小：本工程布局余量极小，任何在 video_clk 域新增的
//      大组合逻辑都会把 sd_card_clk 域挤出 mslices、把 SWNS 从 +0.5ns 拖到
//      红线以下。因此这里只画「矩形/色带」级别的图形，数字与文字交给
//      osd_overlay 复用其已有的字模 ROM（不重复例化）。
//
// 交互：
//   en        模式使能（顶层 SW1 长按 1.2s 翻转，此处在绘制/切换上做门控）
//   key_ini   进入模式单脉冲 -> 距离回 200cm
//   key_step  距离档循环 200 -> 120 -> 60 -> 20 -> 200 cm（短按单脉冲）
//   key_rst   距离档回 200 cm（短按单脉冲）
// ============================================================================
module reverse_assist
(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        de,
    input  wire [11:0] x,
    input  wire [10:0] y,

    input  wire        en,
    input  wire        key_step,     // 切档：短按单脉冲
    input  wire        key_rst,      // 回 200cm：短按单脉冲
    input  wire        key_ini,      // 进入模式：单脉冲，强制回 200cm

    output reg         hit,
    output reg  [2:0]  idx,
    output wire [1:0]  lvl,
    output wire [1:0]  dist_sel,

    output reg         beep_hi       // 1 = 提示音「响」半周期（含 0.5s 上电静默）
);

    // ------------------------------------------------------------------
    // 距离档：2 位有限状态，闭包不越界
    //
    // 历史踩坑：这里曾经用「模式开启后强制清零若干拍」来保证进模式时显示 200，
    // 但 en(=p2_dbn) 在按键松开后仍然保持为 1，顶层那个短按脉冲就永远落在
    // 清零窗口里被吃掉 —— 表现就是「怎么按都是 200」。
    //
    // 现在把责任分开：
    //   * 进模式回到 200：由顶层在翻转 p2_dbn 的那一拍给出 ra_ini 单脉冲；
    //   * 切档：key_step 必须是「按下沿」脉冲（一次按压只来 1 个）；
    //   * 回 200：key_rst 与 key_step 一样是单脉冲，两者天然互斥。
    // 本模块不对 en 做任何计时，en 只作为绘制/切换的使能门控。
    // ------------------------------------------------------------------
    reg [1:0] lv;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)              lv <= 2'd0;
        else if (key_ini)        lv <= 2'd0;   // 进入模式 -> 回 200cm（顶层单脉冲）
        else if (en && key_rst)  lv <= 2'd0;
        else if (en && key_step) begin
            case (lv)
                2'd0:    lv <= 2'd1;
                2'd1:    lv <= 2'd2;
                2'd2:    lv <= 2'd3;
                default: lv <= 2'd0;
            endcase
        end
    end
    assign lvl      = lv;
    assign dist_sel = lv;

    // ------------------------------------------------------------------
    // 提示音节拍器（单一 16 级计数器 + 阈值比较，最小资源）
    // 25.175MHz：1 级 = 100ms（2,517,500 拍）
    //   响半周期 = 1 级（100ms）
    //   停半周期 = 2 级(注意 200ms)/5 级(警告 500ms)/9 级(危险 900ms)
    // 计数到 16 级后归零，保证是闭包、不会卡死。
    // ------------------------------------------------------------------
    localparam [23:0] TICK = 24'd2_517_500;

    reg [3:0]  bp_cnt;      // 档内计数
    reg [3:0]  bp_lim;      // 当前档的停半周期上限
    reg [23:0] bp_cyc;      // 100ms 分频
    reg        bp_ph;       // 0 = 响, 1 = 停
    reg [7:0]  bp_qd;       // 上电静默（0.5s = 5 级）

    wire bp_end = (bp_cnt >= bp_lim);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bp_cnt <= 4'd0;
            bp_lim <= 4'd2;
            bp_cyc <= 24'd0;
            bp_ph  <= 1'b1;
            bp_qd  <= 8'd5;
        end else begin
            // 档位 -> 停半周期上限（lv 为单一路径 2 位寄存器）
            if (lv == 2'd3)      bp_lim <= 4'd9;
            else if (lv == 2'd2) bp_lim <= 4'd5;
            else if (lv == 2'd1) bp_lim <= 4'd2;
            else                 bp_lim <= 4'd2;

            if (bp_cyc == 24'd0) begin
                bp_cyc <= TICK;
                if (bp_qd != 8'd0)
                    bp_qd <= bp_qd - 1'b1;      // 上电静默期
                else begin
                    if (bp_end) begin
                        bp_cnt <= 4'd0;
                        bp_ph  <= ~bp_ph;
                    end else
                        bp_cnt <= bp_cnt + 1'b1;
                end
            end else
                bp_cyc <= bp_cyc - 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            beep_hi <= 1'b0;
        else if (!en || (bp_qd != 8'd0) || (lv == 2'd0))
            beep_hi <= 1'b0;                    // 关闭 / 静默期 / 安全档 -> 不响
        else
            beep_hi <= ~bp_ph;                  // 低频信号，50MHz 域采样无风险
    end

    // ------------------------------------------------------------------
    // 几何（全部矩形，最小组合逻辑）
    // 俯视车道 x 176..463 / y 54..310；车尾参考线 y=300；车头 y=336
    // ------------------------------------------------------------------
    wire ca_on  = (x >= 12'd176) & (x < 12'd464) & (y >= 11'd54) & (y < 11'd310);
    wire ca_in  = (x >= 12'd178) & (x < 12'd462) & (y >= 11'd56) & (y < 11'd308);
    wire ca_ln  = ((x >= 12'd180) & (x < 12'd183)) | ((x >= 12'd457) & (x < 12'd460));
    wire ca_dsh = ca_ln & y[4];

    // 三段警戒区（由远到近）：绿 / 黄 / 橙
    wire zn_grn = (y >= 11'd58)  & (y < 11'd202);
    wire zn_yel = (y >= 11'd202) & (y < 11'd258);
    wire zn_org = (y >= 11'd258) & (y < 11'd300);
    wire zn_ref = (y >= 11'd300) & (y < 11'd304);

    // 障碍物方块：宽 72（x 276..347），高 20，6cm/格 -> 20cm=20px
    //   200cm y 122 / 120cm y 182 / 60cm y 242 / 20cm y 282
    wire [10:0] ob_top = (lv == 2'd0) ? 11'd122 :
                         (lv == 2'd1) ? 11'd182 :
                         (lv == 2'd2) ? 11'd242 : 11'd282;
    // 外框 4px 纯白，内部亮黄；yt 为方块内的行偏移
    wire [10:0] yt    = y - ob_top;
    wire ob_on = (x >= 12'd276) & (x < 12'd348) & (y >= ob_top) & (y < (ob_top + 11'd20));
    wire ob_bd = ob_on & ((yt < 11'd4) | (yt >= 11'd16) |
                          (x < 12'd280) | (x >= 12'd344));

    // 车辆俯视轮廓（车头朝下）x 298..341 / y 306..335
    wire car_bd = ((y >= 11'd324) & (y < 11'd336) & (x >= 12'd300) & (x < 12'd340)) |
                  ((y >= 11'd326) & (y < 11'd336) & (x >= 12'd298) & (x < 12'd342));
    wire car_bk = (y >= 11'd306) & (y < 11'd324) &
                  (((x >= 12'd302) & (x < 12'd338)) |
                   ((y >= 11'd308) & (x >= 12'd304) & (x < 12'd336)));

    // 危险档红色横幅（y 310..336，覆盖车尾，替代"请停车"文字）
    wire hz = (lv == 2'd3) & (y >= 11'd310) & (y < 11'd336) &
              (x >= 12'd240) & (x < 12'd400);

    // ------------------------------------------------------------------
    // 优先级合成
    //   idx: 0 主色  1 暗主色  2 高亮  3 白  4 近黑  5 中灰  6 深灰  7 纯黑
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hit <= 1'b0;
            idx <= 3'd0;
        end else if (!en || !de) begin
            hit <= 1'b0;
            idx <= 3'd0;
        end else if (ob_on) begin
            hit <= 1'b1; idx <= ob_bd ? 3'd3 : 3'd2;   // 白框 + 高亮填充
        end else if (car_bd | car_bk) begin
            hit <= 1'b1; idx <= 3'd3;
        end else if (hz) begin
            hit <= 1'b1; idx <= 3'd2;
        end else if (ca_on) begin
            hit <= 1'b1;
            if (!ca_in)       idx <= 3'd5;   // 外框：中灰
            else if (ca_dsh)  idx <= 3'd5;   // 虚线车道线：中灰
            else if (zn_ref)  idx <= 3'd3;   // 车尾参考线：纯白
            else if (zn_org)  idx <= 3'd1;   // 近段：实心暗橙（危险档转暗红）
            else if (zn_yel)  idx <= 3'd1;   // 中段：同用暗主色（档位色阶）
            else              idx <= 3'd1;   // 远段：实心绿底
        end else begin
            hit <= 1'b0; idx <= 3'd0;
        end
    end

endmodule
