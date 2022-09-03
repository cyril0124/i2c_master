`timescale 1ns/1ns

module test_harness();

//**************************************************************************
//                时钟、复位
//**************************************************************************
reg clk;
reg rst_n;

wire scl;
wire sda;
pullup(scl);
pullup(sda);


parameter U_DLY = 1;
parameter CLK_PERIOD = 83; //10MHz--100 12MHz--83 50MHz--20 48MHz--10

initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

initial begin
    #0 rst_n = 1'b1;
    repeat(4) @(posedge clk);
    rst_n = 1'b0;
    repeat(4) @(posedge clk);
    rst_n = 1'b1;
end


i2c_master_top u_i2c_master_top
(
    .clk(clk),
    .rst_n(rst_n),

    .scl(scl),
    .sda(sda)
);

//**************************************************************************
//                i2c_slave memory 模块例化
//**************************************************************************
M24AA02 memory
(
	.A0(1'b0), 
	.A1(1'b0), 
	.A2(1'b0), 
	.WP(1'b0), 
	.SDA(sda), 
	.SCL(scl), 
	.RESET(1'b0)
);



endmodule
