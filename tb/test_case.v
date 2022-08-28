`timescale 1ns/1ns
`include "test_harness.v"

module test_case();

test_harness u_test_harness();

initial begin
    wait(u_test_harness.init_finish);
    //模拟eeprom 的随机读
    u_test_harness.i2c_eeprom_random_read(8'ha0,16'h12_34);

    //读取一个字节
    fork
        u_test_harness.i2c_recv_one_byte(8'ha0);
        u_test_harness.i2c_sim_wr(64'hac,8'h1);
    join

    //读取8个字节
    fork 
        u_test_harness.i2c_recv_bytes(8'ha0,8'h8);
        u_test_harness.i2c_sim_wr(64'h88_77_66_55_44_33_22_11,8'h8);
    join

    //写入两个字节（含一个地址）
    fork
        u_test_harness.i2c_send_one_byte(8'ha0,8'hd1);
        u_test_harness.i2c_sim_rd(2);
    join

    //写入两个字节（含一个地址）
    fork
        u_test_harness.i2c_send_one_byte(8'hb0,8'hd2);
        u_test_harness.i2c_sim_rd(2);
    join

    //写入四个字节（含一个地址）
    fork
        u_test_harness.i2c_send_bytes(8'hc0,64'haa_0a_a0,8'h3);
        u_test_harness.i2c_sim_rd(4);
    join

    #1000
    $display("\n[%d]simulation done!\n",$time);
    $finish;
end

//**************************************************************************
//                仿真文件生成
//**************************************************************************
initial
begin
    $dumpfile("test_case.vcd");  //生成vcd文件，记录仿真信息
    $dumpvars(0, test_case);     //指定层次数，记录信号，0时刻开始
end 

endmodule