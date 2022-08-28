`timescale 1ns/1ns

/*
    START:          ___
            SDA:       \___
                    _______
            SCL:           \

    ADDR: 0xA2 ==> 1010_0010 
                             1                0                 1                 0                 0                 0                 1                  0
                             |                |                 |                 |                 |                 |                 |                  |
                     _______________                    _________________                                                       _________________
            SDA:    /               \__________________/                 \_____________________________________________________/                 \_________________
                              _______          ________          ________          ________          ________          ________          ________          ________
            SCL:    \________/       \________/        \________/        \________/        \________/        \________/        \________/        \________/        \
    
    ACK:
                                    |
            SDA_IN: ________                   ________
                            \_________________/
            SCL:    ________          ________
                            \________/        \________
    
    STOP:
                            |<------ACK------>|
            SDA_IN: ________                   ________
                            \_________________/
                                                        |    ___
            SDA:    xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx____/ 
            SCL:    ________          ________          ________
                            \________/        \________/
*/

module i2c_master
#(
    parameter FILTER = 1,
    parameter U_DLY = 1,
    parameter PRESCALER = 3 //400KHz = 2500ns = 1250ns *2 = 83ns *15 *2 = 312.5ns *4 *2 = 4*clk(83ns) *4 *2 = 30*clk(10ns) *4 *2
                            //400KHz = 1250ns *2 = 156.25ns *8 *2 = 2*clk(83ns) *8 *2
)
(
    input   wire        clk, 
    input   wire        rst_n,

    input   wire        init_finish,

    // input   wire        scl_in,
    output  reg         scl_out,
    // output  reg         scl_oen,
    input   wire        sda_in,
    output  reg         sda_out,
    output  reg         sda_oen,

    input   wire [7:0]  slave_addr,
    input   wire        i2c_rw,
    input   wire        i2c_begin,

    input   wire        conti_write,
    input   wire        conti_receive,

    input   wire [7:0]  write_data,  //写入数据 send data
    input   wire        write_en,    //允许写入数据标志

    output  reg  [7:0]  read_data,   //读取数据
    output  reg         read_en,     //允许读取数据标志

    output  reg         flag_start,
    output  reg         flag_restar,
    output  reg         flag_ack,
    output  reg         flag_nack,
    output  reg         flag_stop
);

/*
always @(posedge clk or negedge rst_n) 
begin
    if(rst_n == 1'b0) begin
    
    end
    else begin

    end
end
*/
reg [7:0]   scl_cnt;
reg [7:0]   cnt_clk;
reg [3:0]   i2c_begin_dly;
reg         scl_dly;
reg         scl_pos;
reg         scl_neg;
reg [7:0]   cnt_sda;
reg [7:0]   data_send;

wire            sda_filter;
wire            i2c_begin_sig;


reg     [7:0]   curr_state;
reg     [7:0]   next_state;

parameter FILTER_WIDTH = 2;

localparam STATE_IDLE   = 4'h0;
localparam STATE_START  = 4'h1;
localparam STATE_ADDR   = 4'h2;
localparam STATE_ACK0   = 4'h3;
localparam STATE_WR_DAT = 4'h4;
localparam STATE_ACK1   = 4'h5;
localparam STATE_RD_DAT = 4'h6;
localparam STATE_ACK2   = 4'h7;
localparam STATE_NACK   = 4'h8;
localparam STATE_STOP   = 4'h9; 
localparam STATE_RESTART = 4'ha;


//**************************************************************************
//                状态机
//**************************************************************************

always @(posedge clk or negedge rst_n) 
begin
    if(rst_n == 1'b0) begin
        curr_state <= #U_DLY STATE_IDLE;
    end
    else begin
        curr_state <= #U_DLY next_state;
    end
end

always @(*) 
begin
    case(curr_state)
        STATE_IDLE: begin //4'h0
            if(i2c_begin_sig == 1'b1 && init_finish==1'b1)
                next_state = STATE_START;
            else
                next_state = STATE_IDLE;
        end
        STATE_START: begin //4'h1
            if(scl_cnt[7:0] == 8'b1111_1111 && cnt_clk_reload == 1'b1)
                next_state = STATE_ADDR;
            else
                next_state = STATE_START;
        end
        STATE_ADDR: begin //4'h2
            if( cnt_sda[7:0] == 8'h8 && scl_neg == 1'b1)
                next_state = STATE_ACK0;
            else
                next_state =STATE_ADDR;
        end
        STATE_ACK0: begin //4'h3 //还需判断restart
            if(scl_pos == 1'b1 && sda_filter == 1'b0) begin
            // if(scl_neg == 1'b1 && flag_ack == 1'b1) begin
                if(i2c_rw == 1'b0)
                    next_state = STATE_WR_DAT;
                else    
                    next_state = STATE_RD_DAT;
            end
            else if(scl_pos == 1'b1 && sda_filter == 1'b1) 
            // else if(scl_neg == 1'b1 && flag_ack == 1'b0)
                next_state = STATE_STOP;
            else
                next_state = STATE_ACK0;
        end
        STATE_WR_DAT: begin //4'h4
            if(cnt_sda[7:0] == 8'h8 && scl_neg == 1'b1) begin
                if(conti_write == 1'b1)
                    next_state = STATE_ACK1;
                else
                    next_state = STATE_NACK;
            end
            else
                next_state =STATE_WR_DAT;
        end
        STATE_ACK1: begin //4'h5
            if(scl_pos == 1'b1 && sda_filter == 1'b0) begin//slave有响应
                if(i2c_rw == 1'b0) //写状态
                    next_state = STATE_WR_DAT;
                else //写完数据后，想立即读数据，需要restart
                    next_state = STATE_RESTART;
            end
            else if(scl_pos == 1'b1 && sda_filter == 1'b1) //slave无响应
                next_state = STATE_STOP;
            else
                next_state = STATE_ACK1;
        end
        STATE_RD_DAT: begin //4'h6
            if(cnt_sda[7:0] == 8'h8 && scl_neg == 1'b1) begin
                if(conti_receive == 1'b1)
                    next_state = STATE_ACK2;
                else
                    next_state = STATE_NACK;
            end
            else
                next_state = STATE_RD_DAT;
        end
        STATE_ACK2: begin //4'h7
            if(scl_pos == 1'b1)
                next_state = STATE_RD_DAT;
            else
                next_state = STATE_ACK2;
        end
        STATE_NACK: begin //4'h8
            if(scl_pos == 1'b1)
            // if(scl_neg == 1'b1 && flag_nack == 1'b1)
                next_state = STATE_STOP;
            else
                next_state = STATE_NACK;
        end
        STATE_STOP: begin //4'h9
            if(scl_cnt[7:0] == 8'b1111_1111 && cnt_clk_reload==1'b1)
                next_state = STATE_IDLE;
            else
                next_state = STATE_STOP;
        end
        STATE_RESTART: begin //4'ha
            next_state = STATE_START;
        end
        default: next_state = STATE_IDLE;
    endcase
end

//scl输出
always @(posedge clk or negedge rst_n) 
begin
    if(rst_n == 1'b0) begin
        scl_out <= #U_DLY 1'b1;
    end
    else if(curr_state != STATE_IDLE && curr_state != STATE_STOP) begin
        if(scl_cnt[7:0]==8'b1111_1111 && cnt_clk_reload==1'b1)
            scl_out <= #U_DLY ~scl_out;
    end
    else begin
        scl_out <= #U_DLY 1'b1;
    end
end

//sda输出
always @(posedge clk or negedge rst_n) 
begin
    if(rst_n == 1'b0) begin
        sda_out <= #U_DLY 1'b1;
    end
    else if(curr_state == STATE_ACK2) //master响应slave
        sda_out <= #U_DLY 1'b0;
    else begin
        case (curr_state)
            STATE_START: begin 
                if(scl_cnt[7:0] == 8'b0000_1111 && cnt_clk_reload==1'b1)
                    sda_out <= #U_DLY 1'b0;
                else;
            end
            STATE_ADDR: begin
                if(scl_neg == 1'b1 && cnt_sda[7:0] != 8'h08) begin
                    sda_out <= #U_DLY data_send[7];
                    data_send[7:0] <= #U_DLY {data_send[6:0],1'b1};
                end
            end
            STATE_ACK0,
            STATE_ACK1,
            STATE_ACK2: begin
                sda_out <= #U_DLY 1'b0;
            end
            STATE_WR_DAT: begin
                if(scl_neg == 1'b1 && cnt_sda[7:0] != 8'h08) begin
                    sda_out <= #U_DLY data_send[7];
                    data_send[7:0] <= #U_DLY {data_send[6:0],1'b1};
                end
            end
            STATE_NACK: begin
                if(scl_cnt[7:0] == 8'b011_1111 && cnt_clk_reload == 1'b1) //提前拉低，防止触发START条件
                    sda_out <= #U_DLY 1'b0;
            end
            STATE_STOP: begin
                if(scl_cnt[7:0] == 8'b0000_1111 && cnt_clk_reload==1'b1)
                    sda_out <= #U_DLY 1'b1;
            end
            default: begin
                sda_out <= #U_DLY 1'b1;
            end
        endcase
    end
end

always @(posedge clk or negedge rst_n) 
begin
    if(rst_n == 1'b0) begin
        sda_oen <= #U_DLY 1'b1;
    end
    else begin
        case (curr_state)
            STATE_ACK0,STATE_ACK1,STATE_ACK2,STATE_NACK: begin
                sda_oen <= #U_DLY 1'b0;
            end
            default: begin
                sda_oen <= #U_DLY 1'b1;
            end
        endcase
    end
end

always @(posedge clk or negedge rst_n) 
begin
    if(rst_n == 1'b0) begin
        data_send[7:0] <= #U_DLY 8'h00;
    end
    else begin
        case (curr_state)
            STATE_START: 
                data_send[7:0] <= #U_DLY {slave_addr[7:1],i2c_rw};
            STATE_ACK0,
            STATE_ACK1: begin
                if(write_en == 1'b1)
                    data_send[7:0] <= #U_DLY write_data[7:0];
                else
                    data_send[7:0] <= #U_DLY data_send[7:0];
            end
        endcase
    end
end

//**************************************************************************
//                i2c_begin
//**************************************************************************
assign i2c_begin_sig = (~i2c_begin_dly[3]&i2c_begin_dly[2]);

always @(posedge clk or negedge rst_n) 
begin
    if(rst_n == 1'b0) begin
        i2c_begin_dly[3:0] <= #U_DLY 4'b0000;
    end
    else if(i2c_begin == 1'b1) begin
        i2c_begin_dly[3:0] <= #U_DLY {i2c_begin_dly[2:0],1'b1};
    end
    else begin
        i2c_begin_dly[3:0] <= #U_DLY {i2c_begin_dly[2:0],1'b0};
    end
end


//**************************************************************************
//                scl信号
//**************************************************************************
wire cnt_clk_reload;

assign cnt_clk_reload = (cnt_clk[7:0] == PRESCALER) ? 1'b1:1'b0;

always @(posedge clk or negedge rst_n) 
begin
    if(rst_n == 1'b0) begin
        cnt_clk[7:0] <= #U_DLY 8'h00;
    end
    else begin
        if(curr_state == STATE_IDLE)
            cnt_clk[7:0] <= #U_DLY 8'h00;
        else begin
            if(cnt_clk[7:0] == PRESCALER)
                cnt_clk[7:0] <= #U_DLY 8'h00;
            else
                cnt_clk[7:0] <= #U_DLY cnt_clk[7:0] + 1'b1;
        end
    end
end

always @(posedge clk or negedge rst_n) 
begin
    if(rst_n == 1'b0) begin
        scl_cnt[7:0] <= #U_DLY 8'b0000_0001;
    end
    else begin
        if(cnt_clk[7:0] == PRESCALER && scl_cnt[7:0] == 8'b1111_1111)
            scl_cnt[7:0] <= #U_DLY 8'b0000_0001;
        else if(cnt_clk[7:0] == PRESCALER)
            scl_cnt[7:0] <= #U_DLY {scl_cnt[6:0],1'b1};
        else
            scl_cnt[7:0] <= #U_DLY scl_cnt[7:0];
    end
end

always @(posedge clk or negedge rst_n) 
begin
    if(rst_n == 1'b0) begin
        scl_dly <= #U_DLY 1'b1;
    end
    else begin
        scl_dly <= #U_DLY scl_out;
    end
end

always @(posedge clk or negedge rst_n) 
begin
    if(rst_n == 1'b0)
        scl_pos <= #U_DLY 1'b0;
    else if(scl_out == 1'b1 && scl_dly == 1'b0)
        scl_pos <= #U_DLY 1'b1;
    else
        scl_pos <= #U_DLY 1'b0;
end

always @(posedge clk or negedge rst_n) 
begin
    if(rst_n == 1'b0)
        scl_neg <= #U_DLY 1'b0;
    else if(scl_out == 1'b0 && scl_dly == 1'b1)
        scl_neg <= #U_DLY 1'b1;
    else
        scl_neg <= #U_DLY 1'b0;
end

//**************************************************************************
//                sda数据计数
//**************************************************************************
always @(posedge clk or negedge rst_n) 
begin
    if(rst_n == 1'b0) begin
        cnt_sda[7:0] <= #U_DLY 8'h00;
    end
    else if(cnt_sda[7:0] == 8'h8 && scl_pos == 1'b1) begin
        cnt_sda[7:0] <= #U_DLY 8'h0;
    end
    else if((curr_state == STATE_ADDR || curr_state == STATE_WR_DAT || curr_state == STATE_RD_DAT)&& scl_pos == 1'b1) begin
        cnt_sda[7:0] <= #U_DLY cnt_sda[7:0] + 1'b1;
    end 
    else if(curr_state == STATE_START || curr_state == STATE_STOP || curr_state == STATE_RESTART) begin
        cnt_sda[7:0] <= #U_DLY 8'h0;
    end
end

//**************************************************************************
//                sda_in滤波
//**************************************************************************
generate
    if(FILTER == 1'b1) begin
        reg sda_filter_reg;
        assign sda_filter = sda_filter_reg;
        reg [FILTER_WIDTH-1:0] sda_pipe;

        always @(posedge clk or negedge rst_n) 
        begin
            if(rst_n == 1'b0) begin
                sda_pipe[FILTER_WIDTH-1:0] <= #U_DLY {FILTER_WIDTH{1'b1}};
                sda_filter_reg <= #U_DLY 1'b1;
            end
            else begin
                sda_pipe[FILTER_WIDTH-1:0] <= #U_DLY {sda_pipe[FILTER_WIDTH-2:0],sda_in};
                if(&sda_pipe[FILTER_WIDTH-1:0] == 1'b1)
                    sda_filter_reg <=  #U_DLY 1'b1;
                else if(|sda_pipe[FILTER_WIDTH-1:0] == 1'b0)
                    sda_filter_reg <= #U_DLY 1'b0;
            end
        end
    end
    else begin
        assign sda_filter = sda_in;
    end
endgenerate

//**************************************************************************
//                sda数据读取
//**************************************************************************
always @(posedge clk or negedge rst_n) 
begin
    if(rst_n == 1'b0) begin
        read_data[7:0] <= #U_DLY 8'h00;
    end
    else if(curr_state == STATE_RD_DAT && scl_pos == 1'b1) 
        read_data[7:0] <= #U_DLY {read_data[6:0],sda_filter};
    else if(curr_state == STATE_IDLE)
        read_data[7:0] <= #U_DLY 8'h00;
    else
        read_data[7:0] <= #U_DLY read_data[7:0];
end

always @(posedge clk or negedge rst_n) 
begin
    if(rst_n == 1'b0) begin
        read_en <= #U_DLY 1'b0;
    end
    else if(curr_state == STATE_RD_DAT && (next_state == STATE_ACK2 || next_state == STATE_NACK))
        read_en <= #U_DLY 1'b1;
    else
        read_en <= #U_DLY 1'b0;
end



//**************************************************************************
//                flag信号输出
//**************************************************************************

always @(posedge clk or negedge rst_n) 
begin
    if(rst_n == 1'b0) begin
        flag_ack <= #U_DLY 1'b0;
        flag_nack <= #U_DLY 1'b0;
    end
    else if (
            (curr_state == STATE_ADDR   && next_state == STATE_ACK0) ||
            (curr_state == STATE_WR_DAT && next_state == STATE_ACK1) ||
            (curr_state == STATE_RD_DAT && next_state == STATE_ACK2)
        )
        flag_ack <= #U_DLY 1'b1;
    else if((curr_state == STATE_WR_DAT || curr_state == STATE_RD_DAT) && next_state == STATE_NACK)
        flag_nack <= #U_DLY 1'b1;
    else begin
        flag_ack <= #U_DLY 1'b0;
        flag_nack <= #U_DLY 1'b0;
    end
end

// always @(posedge clk or negedge rst_n) 
// begin
//     if(rst_n == 1'b0) begin
//         flag_ack <= #U_DLY 1'b0;
//         flag_nack <= #U_DLY 1'b0;
//     end
//     else if (
//             (curr_state == STATE_ACK0 ) ||
//             (curr_state == STATE_ACK1 ) ||
//             (curr_state == STATE_ACK2 )
//     ) begin
//         if(scl_pos == 1'b1 && sda_filter == 1'b0)
//             flag_ack <= #U_DLY 1'b1;
//     end
//     else if(curr_state == STATE_NACK)
//         flag_nack <= #U_DLY 1'b1;
//     else begin
//         flag_ack <= #U_DLY 1'b0;
//         flag_nack <= #U_DLY 1'b0;
//     end
// end

always @(posedge clk or negedge rst_n) 
begin
    if(rst_n == 1'b0) begin
        flag_start <= #U_DLY 1'b0;
    end
    else if(curr_state == STATE_IDLE && next_state == STATE_START)
        flag_start <= #U_DLY 1'b1;
    else
        flag_start <= #U_DLY 1'b0;
end

always @(posedge clk or negedge rst_n) 
begin
    if(rst_n == 1'b0) begin
        flag_stop <= #U_DLY 1'b0;
    end
    else if(curr_state == STATE_STOP && next_state == STATE_IDLE)
        flag_stop <= #U_DLY 1'b1;
    else   
        flag_stop <= #U_DLY 1'b0;
end

always @(posedge clk or negedge rst_n) 
begin
    if(rst_n == 1'b0) begin 
        flag_restar <= #U_DLY 1'b0;
    end
    else if(curr_state == STATE_ACK1 && next_state == STATE_RESTART)
        flag_restar <= #U_DLY 1'b1;
    else
        flag_restar <= #U_DLY 1'b0;
end


endmodule

