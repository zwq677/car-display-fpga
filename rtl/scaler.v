`timescale 1ns / 1ps
// ============================================================================
// scaler.v —— 最近邻图像缩放器（任意分辨率 -> 640x480）
//
// 赛题一扩展项③「图片缩放适配」：把 SD 卡读出的任意分辨率 BMP 流式缩放
// 到 HDMI 输出分辨率 640x480。
//
// 算法：最近邻插值，用 Bresenham 累加器实现"源驱动"的缩放映射，
//   纯加减、无乘除法、无 DSP。水平方向逐像素流式处理（列重复/跳列），
//   垂直方向配合一行缓存（line buffer）实现行重复/跳行。
//
// 时序优化（关键）：
//   水平缩放拆成两拍流水 —— H_CMP 拍做"h_acc >= src_width"比较，
//   H_WRITE 拍用寄存的比较结果写行缓存，避免单拍 6 级组合逻辑在
//   sd_card_clk(100MHz) 下违例（10.9ns > 10ns）。
//
// 行缓存：640x24bit，用 LUT 分布式 RAM（不占 EMB，避免语音 ROM 已占
//   61/64 EMB 后进一步挤压布局）。
// ============================================================================
module scaler (
    input  wire        clk,
    input  wire        rst,
    input  wire        frame_start,    // 一帧开始脉冲（bmp_read 的 write_req）
    input  wire [15:0] src_width,      // 源图宽（bmp_read 解析的真实宽）
    input  wire [15:0] src_height,     // 源图高
    input  wire        src_valid,      // 源像素有效（1 拍 1 像素，BMP 自底向上）
    input  wire [23:0] src_data,       // 源像素 RGB
    output reg         dst_valid,      // 目标像素有效
    output reg  [23:0] dst_data,       // 目标像素 RGB（640x480）
    output reg         dst_done        // 一帧缩放完成脉冲
);

    // ---- 目标分辨率固定 640x480 ----
    localparam [15:0] DST_W = 16'd640;
    localparam [15:0] DST_H = 16'd480;

    // ---- 状态机 ----
    localparam [2:0] ST_IDLE     = 3'd0;
    localparam [2:0] ST_READ_PX  = 3'd1;
    localparam [2:0] ST_H_CMP    = 3'd2;
    localparam [2:0] ST_H_WRITE  = 3'd3;
    localparam [2:0] ST_V_INC    = 3'd4;
    localparam [2:0] ST_V_LOOP   = 3'd5;
    localparam [2:0] ST_V_OUT    = 3'd6;
    localparam [2:0] ST_NEXT_ROW = 3'd7;

    reg [2:0] state;

    // ---- 行缓存（LUT 分布式 RAM，640x24bit，异步读）----
    reg [23:0] line_buf [0:639];  /* fehdl ram_style="distributed" */
    reg [9:0]  buf_rd;            // 读地址
    wire [23:0] buf_rdata = line_buf[buf_rd];   // 异步读（组合）

    // ---- 水平 Bresenham ----
    reg [10:0] h_acc;             // 水平累加器（每源像素 +640，写一次 -src_width）
    reg        h_ge;              // 比较结果：h_acc >= src_width（寄存一拍）
    reg [23:0] px_hold;           // 锁存的源像素
    reg [15:0] px_cnt;            // 当前源行已读源像素数
    reg [9:0]  col_cnt;           // 行缓存已写列数（0..639）

    // ---- 垂直 Bresenham ----
    reg [10:0] v_acc;             // 垂直累加器（每源行 +480，写一行 -src_height）
    reg [15:0] row_cnt;           // 已处理源行数
    reg        last_row;          // 是否最后一个源行（ST_V_LOOP 提前一拍寄存，拆关键路径）
    reg        vout_cnt;          // V_OUT 节流计数（每 2 拍输出 1 个，避免写 FIFO 溢出）

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= ST_IDLE;
            buf_rd       <= 10'd0;
            h_acc        <= 11'd0;
            h_ge         <= 1'b0;
            px_hold      <= 24'd0;
            px_cnt       <= 16'd0;
            col_cnt      <= 10'd0;
            v_acc        <= 11'd0;
            row_cnt      <= 16'd0;
            last_row     <= 1'b0;
            vout_cnt     <= 1'b0;
            dst_valid    <= 1'b0;
            dst_data     <= 24'd0;
            dst_done     <= 1'b0;
        end else begin
            dst_valid <= 1'b0;
            dst_done  <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (frame_start) begin
                        buf_rd  <= 10'd0;
                        h_acc   <= 11'd0;
                        h_ge    <= 1'b0;
                        px_hold <= 24'd0;
                        px_cnt  <= 16'd0;
                        col_cnt <= 10'd0;
                        v_acc   <= 11'd0;
                        row_cnt <= 16'd0;
                        last_row <= 1'b0;
                        state   <= ST_READ_PX;
                    end
                end

                ST_READ_PX: begin
                    if (src_valid) begin
                        px_hold <= src_data;
                        px_cnt  <= px_cnt + 16'd1;
                        h_acc   <= h_acc + DST_W;
                        state   <= ST_H_CMP;
                    end
                end

                ST_H_CMP: begin
                    h_ge  <= (h_acc >= src_width);
                    state <= ST_H_WRITE;
                end

                ST_H_WRITE: begin
                    if (h_ge) begin
                        // 写行缓存（放大时连续写多次，每次写后回 H_CMP 重新比较）
                        line_buf[col_cnt] <= px_hold;
                        col_cnt <= col_cnt + 10'd1;
                        h_acc   <= h_acc - src_width;
                        state   <= ST_H_CMP;
                    end else begin
                        // 当前源像素写完了：判断源行是否读完
                        if (px_cnt >= src_width)
                            state <= ST_V_INC;   // 源行读完
                        else
                            state <= ST_READ_PX; // 等下一个源像素
                    end
                end

                ST_V_INC: begin
                    v_acc <= v_acc + DST_H;
                    state <= ST_V_LOOP;
                end

                ST_V_LOOP: begin
                    if (v_acc >= src_height) begin
                        // 写这行（从行缓存读输出）
                        v_acc    <= v_acc - src_height;
                        buf_rd   <= 10'd0;
                        vout_cnt <= 1'b0;   // 节流计数器复位，第一拍即输出
                        state    <= ST_V_OUT;
                    end else begin
                        // 垂直缩小：跳行。提前一拍寄存"是否最后一行"，
                        // 避免 row_cnt+1>=src_height 的比较直接驱动 col_cnt 等
                        // 高扇出寄存器的使能端，形成 6 级组合逻辑违例。
                        last_row <= (row_cnt + 16'd1 >= src_height);
                        state    <= ST_NEXT_ROW;
                    end
                end

                ST_V_OUT: begin
                    // 节流：每 2 拍输出 1 个像素。行缓存 640x24bit 的异步读 mux
                    // 本身不慢，但下游 frame_fifo_write 的写 FIFO 深度仅 512、
                    // burst 读 256，若这里连续 640 拍无间隔输出会把 FIFO 写溢出、
                    // 丢像素导致 write_finish 写不满 307200（屏幕黑/闪烁）。
                    if (vout_cnt == 1'b0) begin
                        dst_valid <= 1'b1;
                        dst_data  <= buf_rdata;
                        if (buf_rd == 10'd639) begin
                            state <= ST_V_LOOP;
                        end else begin
                            buf_rd <= buf_rd + 10'd1;
                        end
                    end
                    vout_cnt <= ~vout_cnt;
                end

                ST_NEXT_ROW: begin
                    if (last_row) begin
                        // 所有源行处理完，帧完成
                        dst_done      <= 1'b1;
                        state         <= ST_IDLE;
                    end else begin
                        row_cnt <= row_cnt + 16'd1;
                        px_cnt  <= 16'd0;
                        col_cnt <= 10'd0;
                        h_acc   <= 11'd0;
                        h_ge    <= 1'b0;
                        state   <= ST_READ_PX;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
