`timescale 1ns/1ns
// `include "../src/i2c_master.v"

module i2c_master_tb; 

//**************************************************************************
//                时钟、复位
//**************************************************************************
reg clk;
reg rst_n;

parameter U_DLY = 1;
parameter CLK_PERIOD = 83; //10MHz--100 12MHz--83 50MHz--20

initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

initial begin
    #0 rst_n = 1'b1;
    #(CLK_PERIOD*2) rst_n = 1'b0;
    #(CLK_PERIOD/2) rst_n = 1'b1;
end

//**************************************************************************
//                i2c_master 读写行为控制
//**************************************************************************

task generate_i2c_start;
    input [15:0] begin_time;
    begin
        i2c_begin = 1'b1;
        i2c_begin_finish = 1'b0;
        #(begin_time);
        i2c_begin = 1'b0;
        i2c_begin_finish = 1'b1;
    end
endtask

task i2c_send_one_byte;
    input [7:0] addr;
    input [7:0] byte;
    begin
        #0 begin
            conti_write = 1'b0;
            i2c_rw = 1'b0;
        end
        generate_i2c_start(CLK_PERIOD*2);
        wait(flag_start);

        i2c_slave_addr[7:0] = addr[7:0];
        wait(flag_ack);

        write_data[7:0] = byte[7:0];
        @(posedge clk) #U_DLY
        write_en = 1'b1;
        @(posedge clk) #U_DLY
        write_en = 1'b0;
        wait(flag_nack);

        wait(flag_stop);
        // $strobe("\n[%d]addr:0x%h byte:0x%h i2c_send_one_byte done!\n",$time,addr,byte);
    end
endtask

task i2c_send_bytes;
    input [7:0] addr;
    input [63:0] bytes;
    input [7:0] num;
    reg [63:0] temp_bytes;
    integer i;
    begin
        #0 begin
            conti_write = 1'b1;
            temp_bytes[63:0] = bytes[63:0];
            i2c_rw = 1'b0;
        end
        generate_i2c_start(CLK_PERIOD*2);
        wait(flag_start);

        i2c_slave_addr[7:0] = addr[7:0];
        wait(flag_ack);

        for(i=0;i<num;i++) begin
            write_data[7:0] <= bytes[7:0];
            bytes[63:0] <= bytes[63:0] >> 8;

            @(posedge clk) #U_DLY
            write_en = 1'b1;
            @(posedge clk) #U_DLY
            write_en = 1'b0;

            if(i==num-1) begin
                conti_write = 1'b0;
                wait(flag_nack);
            end
            else begin
                conti_write = 1'b1;
                wait(flag_ack);
            end
        end

        wait(flag_nack);

        wait(flag_stop);
        // $strobe("\n[%d]addr:0x%h byte:0x%h i2c_send_bytes done!\n",$time,addr,temp_bytes);
    end
endtask

task i2c_recv_one_byte;
    input [7:0] addr;
    reg [7:0] recv_data;
    begin
        #0 begin
            recv_data[7:0] = 8'h00;
            i2c_rw = 1'b1;
            conti_receive = 1'b0;
        end
        generate_i2c_start(CLK_PERIOD*2);
        wait(flag_start);

        i2c_slave_addr[7:0] = addr[7:0];
        wait(flag_ack);

        wait(read_en);
        recv_data[7:0] = read_data[7:0];
        
        wait(flag_stop);
        $strobe("\n[%d]byte:0x%h i2c_recv_one_byte done!\n",$time,recv_data);
    end
endtask

task i2c_recv_bytes;
    input [7:0] addr;
    input [7:0] num;
    reg [7:0] recv_data;
    integer i;
    begin
        #0 begin
            recv_data[7:0] = 8'h00;
            i2c_rw = 1'b1;
            conti_receive = 1'b1;
        end
        $strobe("\n[%d]addr:0x%h num:0x%h i2c_recv_bytes start!>>>",$time,addr,num);
        generate_i2c_start(CLK_PERIOD*2);
        wait(flag_start);

        i2c_slave_addr[7:0] = addr[7:0];
        wait(flag_ack);

        for(i=0;i<num;i++) begin
            wait(read_en);
            recv_data[7:0] <= read_data[7:0];
            $strobe("[%d]byte:0x%h",$time,recv_data);
            @(posedge scl_out); //等待下一波数据
        end

        conti_receive = 1'b0;

        wait(flag_nack);
        wait(flag_stop);
        $strobe("[%d]i2c_recv_bytes done!<<<\n",$time);
    end
endtask

task i2c_eeprom_random_read;
    input [7:0] addr;
    input [15:0] word_address;
    reg [7:0] recv_data;
    begin
        #0 begin
            i2c_rw = 1'b0; //写
            conti_write = 1'b1;
        end
        generate_i2c_start(CLK_PERIOD*2);
        wait(flag_start);

        i2c_slave_addr[7:0] = addr[7:0];
        wait(flag_ack);

        write_data[7:0] = word_address[15:8];
        @(posedge clk) #U_DLY
        write_en = 1'b1;
        @(posedge clk) #U_DLY
        write_en = 1'b0;
        wait(flag_ack);

        write_data[7:0] = word_address[7:0];
        @(posedge clk) #U_DLY
        write_en = 1'b1;
        @(posedge clk) #U_DLY
        write_en = 1'b0;
        wait(flag_ack);

        i2c_rw = 1'b1; //读
        wait(flag_restar);

        wait(flag_ack); //等待i2c发送读地址
        conti_write = 1'b0;

        wait(read_en);
        recv_data[7:0] = read_data[7:0];

        wait(flag_stop);
        $strobe("\n[%d]addr:0x%h word_addr:0x%h byte:0x%h i2c_eeprom_random_read done!\n",$time,addr,word_address,recv_data);
    end
endtask

//读回数据测试
task i2c_sim_rd;
    input [7:0] num;
    reg [7:0] sim_rd;
    integer i;
    integer j;
    begin
        #0 begin
            sim_rd[7:0] = 8'h00;
        end
        $strobe("\n[%d]i2c_sim_rd start!>>>",$time);
        wait(i2c_begin_finish);
        
        for(i=0;i<num;i++) begin
            
            //上升沿采样数据
            for(j=0;j<8;j++) begin
                @(posedge scl_out)
                sim_rd[7:0] = {sim_rd[6:0],sda_out};
            end
            //等待ack
            @(posedge scl_out);

            $strobe("[%d]rd:0x%h",$time,sim_rd);
        end
        
        $strobe("[%d]i2c_sim_rd done!<<<\n",$time);
    end
endtask

//写入数据测试
task i2c_sim_wr;
    input [63:0] bytes;
    input [7:0] num;
    reg [7:0] data_send;
    integer i;
    integer j;
    begin
        // $strobe("\n[%d]i2c_sim_wr start!>>>",$time);
        wait(i2c_begin_finish);

        for(i=0;i<num;i++) begin
            wait(flag_ack);
            sda_in <= 1'b0;

            data_send[7:0] <= #U_DLY bytes[7:0];
            bytes[63:0] <= #U_DLY bytes[63:0] >> 8;
            // $strobe("\n[%d]i2c_sim_wr send:0x%h!",$time,bytes[7:0]);
            for(j=0;j<8;j++) begin
                @(negedge scl_out);
                sda_in <= #U_DLY data_send[7];
                data_send[7:0] <= #U_DLY data_send[7:0] << 1;
            end
        end
        // $strobe("\n[%d]i2c_sim_wr done!<<<",$time);

    end
endtask


initial begin
    #(CLK_PERIOD*10);
    init_finish = 1'b1;

    //模拟eeprom 的随机读
    i2c_eeprom_random_read(8'ha0,16'h12_34);

    //读取一个字节
    fork
        i2c_recv_one_byte(8'ha0);
        i2c_sim_wr(64'hac,8'h1);
    join

    //读取8个字节
    fork 
        i2c_recv_bytes(8'ha0,8'h8);
        i2c_sim_wr(64'h88_77_66_55_44_33_22_11,8'h8);
    join

    //写入两个字节（含一个地址）
    fork
        i2c_send_one_byte(8'ha0,8'hd1);
        i2c_sim_rd(2);
    join

    //写入两个字节（含一个地址）
    fork
        i2c_send_one_byte(8'hb0,8'hd2);
        i2c_sim_rd(2);
    join

    //写入四个字节（含一个地址）
    fork
        i2c_send_bytes(8'hc0,64'haa_0a_a0,8'h3);
        i2c_sim_rd(4);
    join
end




//**************************************************************************
//                i2c_master 模块例化
//**************************************************************************
reg       init_finish;
reg       i2c_begin;
reg       i2c_begin_finish;
reg       i2c_rw;
reg [7:0] i2c_slave_addr;
reg [7:0] write_data;
reg       write_en;
wire [7:0] read_data;
wire       read_en;
reg       conti_write;
reg       conti_receive;

wire scl_out;
reg  sda_in;
wire sda_out;

wire      flag_start;
wire      flag_restar;
wire      flag_ack;
wire      flag_nack;
wire      flag_stop;

initial begin
    #0 begin
        i2c_begin = 1'b0;
        i2c_begin_finish = 1'b0;
        i2c_rw = 1'b0;
        write_en = 1'b0;
        write_data[7:0] = 8'h00;
        conti_write = 1'b0;
        conti_receive = 1'b0;
        i2c_slave_addr[7:0] = 8'h00;
        sda_in = 1'b0;
    end
end




i2c_master#(
    .PRESCALER  ( 3 )
)u_i2c_master(
    .clk        ( clk        ),
    .rst_n      ( rst_n      ),

    .init_finish(init_finish),
    .scl_in     (            ),
    .scl_out    ( scl_out    ),
    .sda_in     ( sda_in     ),
    .sda_out    ( sda_out    ),

    .slave_addr ( i2c_slave_addr ),
    .i2c_rw     ( i2c_rw         ),
    .i2c_begin  ( i2c_begin      ),

    .conti_write  ( conti_write   ),
    .conti_receive( conti_receive ),

    .write_data ( write_data ),
    .write_en   ( write_en   ),
    .read_data  ( read_data  ),
    .read_en    ( read_en    ),

    .flag_start ( flag_start ),
    .flag_restar( flag_restar),
    .flag_ack   ( flag_ack   ),
    .flag_nack  ( flag_nack  ),
    .flag_stop  ( flag_stop  ) 
);




//**************************************************************************
//                仿真文件生成
//**************************************************************************

initial
begin
    $dumpfile("i2c_master_tb.vcd");  //生成vcd文件，记录仿真信息
    $dumpvars(0, i2c_master_tb);     //指定层次数，记录信号，0时刻开始
    #650000 
    $display("\n[%d]simulation done!\n",$time);
    $finish;
end 
endmodule

