`timescale 1ns/1ns

module i2c_master_top
(
    input   wire        clk, 
    input   wire        rst_n,

    inout               scl,
    inout               sda
);

parameter U_DLY = 1;
parameter CLK_PERIOD = 83; //10MHz--100 12MHz--83 50MHz--20 48MHz--10

task generate_i2c_start;
    input [15:0] begin_time;
    begin
        i2c_begin = 1'b1;
        i2c_begin_finish = 1'b0;
        // #(begin_time);
        @(posedge clk);
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

        i2c_slave_addr[7:0] = addr[7:0];

        @(posedge write_rdy);
        write_data[7:0] = byte[7:0];
        @(posedge clk) #U_DLY
        write_en = 1'b1;
        @(posedge clk) #U_DLY
        write_en = 1'b0;

        @(posedge flag_stop);
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

        i2c_slave_addr[7:0] = addr[7:0];

        for(i=0;i<num;i++) begin
            @(posedge write_rdy);
            write_data[7:0] <= bytes[7:0];
            bytes[63:0] <= bytes[63:0] >> 8;

            @(posedge clk) #U_DLY
            write_en = 1'b1;
            @(posedge clk) #U_DLY
            write_en = 1'b0;

            if(i==num-1)
                conti_write = 1'b0;
        end
        
        @(posedge flag_stop);
        $strobe("\n[%d]addr:0x%h byte:0x%h i2c_send_bytes done!\n",$time,addr,temp_bytes);
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
        @(posedge flag_ack);

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

        i2c_slave_addr[7:0] = addr[7:0];

        for(i=0;i<num;i=i) begin
            @(posedge read_en);
            recv_data[7:0] <= read_data[7:0];
            $strobe("[%d]byte:0x%h",$time,recv_data);
            i=i+1;
            if(i==num-1)
                conti_receive = 1'b0;
        end

        @(posedge flag_stop);
        $strobe("[%d]i2c_recv_bytes done!<<<\n",$time);
    end
endtask

task i2c_eeprom_random_read;
    input [7:0] addr;
    input [15:0] word_address;
    input [7:0] word_addr_num;
    reg [7:0] recv_data;
    begin
        #0 begin
            i2c_rw = 1'b0; //???
            conti_write = 1'b1;
        end
        generate_i2c_start(CLK_PERIOD*2);
        // wait(flag_start);

        i2c_slave_addr[7:0] = addr[7:0];
        // @(posedge flag_ack);

        if(word_addr_num[7:0] == 8'h02) begin
            @(posedge write_rdy);
            write_data[7:0] = word_address[15:8];
            @(posedge clk) #U_DLY
            write_en = 1'b1;
            @(posedge clk) #U_DLY
            write_en = 1'b0;
            // @(posedge flag_ack);
        end
        
        if(word_addr_num[7:0] == 8'h02 || word_addr_num[7:0] == 8'h01) begin
            @(posedge write_rdy);
            write_data[7:0] = word_address[7:0];
            @(posedge clk) #U_DLY
            write_en = 1'b1;
            @(posedge clk) #U_DLY
            write_en = 1'b0;
            // @(posedge flag_ack);
        end

        @(posedge write_rdy);
        i2c_rw = 1'b1; //???

        wait(flag_restar);

        @(posedge flag_ack); //??????i2c???????????????
        conti_write = 1'b0;

        wait(read_en);
        recv_data[7:0] = read_data[7:0];

        wait(flag_stop);
        if(word_addr_num[7:0] == 8'h02)
            $strobe("\n[%d]addr:0x%h word_addr:0x%h byte:0x%h i2c_eeprom_random_read done!\n",$time,addr,word_address,recv_data);
        if(word_addr_num[7:0] == 8'h01)
            $strobe("\n[%d]addr:0x%h word_addr:0x%h byte:0x%h i2c_eeprom_random_read done!\n",$time,addr,word_address[7:0],recv_data);
    end
endtask

//??????????????????
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
            
            //?????????????????????
            for(j=0;j<8;j++) begin
                @(posedge scl_oen)
                sim_rd[7:0] = {sim_rd[6:0],sda_out};
            end
            //??????ack
            @(posedge scl_oen);

            $strobe("[%d]rd:0x%h",$time,sim_rd);
        end
        
        $strobe("[%d]i2c_sim_rd done!<<<\n",$time);
    end
endtask

//??????????????????
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
            @(posedge flag_ack);
            sda_in <= 1'b0;

            data_send[7:0] <= #U_DLY bytes[7:0];
            bytes[63:0] <= #U_DLY bytes[63:0] >> 8;
            // $strobe("\n[%d]i2c_sim_wr send:0x%h!",$time,bytes[7:0]);
            for(j=0;j<8;j++) begin
                @(negedge scl_oen);
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
end




//**************************************************************************
//                i2c_master ????????????
//**************************************************************************
reg       init_finish;
reg       i2c_begin;
reg       i2c_begin_finish;
reg       i2c_rw;
reg [7:0] i2c_slave_addr;
reg [7:0] write_data;
reg       write_en;
wire      write_rdy;
wire [7:0] read_data;
wire       read_en;
reg       conti_write;
reg       conti_receive;

wire scl_oen;
reg  sda_in;
wire sda_out;
wire sda_oen;

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

wire sda_in_master;
wire scl_in_master;

assign sda = (sda_oen == 1'b0) ? 1'b0 : 1'bz;
assign sda_in_master = sda;
assign scl = (scl_oen == 1'b0) ? 1'b0 : 1'bz;
assign scl_in_master = scl;

i2c_master#(
    .PRESCALER  ( 7 )
)u_i2c_master(
    .clk        ( clk        ),
    .rst_n      ( rst_n      ),

    .init_finish( init_finish   ),
    .scl_in     ( 1'b1 ),
    .scl_oen    ( scl_oen       ),
    .sda_in     ( sda_in_master ), //??????i2c slave???,??????.sda_in()???????????????sda,????????????????????????sda_in sda_in_master
    .sda_oen    ( sda_oen       ),

    .slave_addr ( i2c_slave_addr ),
    .i2c_rw     ( i2c_rw         ),
    .i2c_begin  ( i2c_begin      ),

    .conti_write  ( conti_write   ),
    .conti_receive( conti_receive ),

    .write_data ( write_data ),
    .write_en   ( write_en   ),
    .write_rdy  ( write_rdy  ),
    .read_data  ( read_data  ),
    .read_en    ( read_en    ),

    .flag_start ( flag_start ),
    .flag_restar( flag_restar),
    .flag_ack   ( flag_ack   ),
    .flag_nack  ( flag_nack  ),
    .flag_stop  ( flag_stop  ) 
);





endmodule