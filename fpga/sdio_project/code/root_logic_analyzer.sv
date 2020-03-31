/*
 * Author:	Dmitriy 'Balmer' Poskryakov
 * Created:	2020
 * License: MIT License
*/

module root_logic_analyzer (input clock50mhz,
	input uart_rx_pin,
	output reg uart_tx_pin,
	
	//Светодиоды
	output bit led110,
	output reg led111,
	output reg led114,
	output reg led115,
	
	input reg sd_clock,
	inout wire sd_cmd,
	inout wire[3:0] sd_data
	);

	
initial led110 = 0;
initial led111 = 0;
initial led115 = 0;

bit clock200mhz;

pll200mhz pll200mhz0(
	.inclk0(clock50mhz),
	.c0(clock200mhz),
	.locked());

localparam UART_CLKS_PER_BIT = 100;//500 000 bps --ok

localparam CLOCKS_PER_TICK_1US = 50;
localparam CLOCKS_PER_TICK_1MS = 50000;
	
bit uart_rx_received;
byte uart_rx_byte;

bit uart_tx_send_byte = 0;
bit uart_tx_active;
byte uart_tx_byte;

//Команды, приходящие с UART
//Уже буферизированные.
bit dev_command_started;
bit dev_command_processing;
byte dev_command;
bit dev_busy;
bit dev_command_data_signal;
byte dev_data;
bit signal_1ms;
bit signal_1us;

//
bit dev_command_started_la;
bit dev_command_processing_la;
bit dev_command_data_signal_la;
bit dev_busy_la;
bit led_full_la;
bit uart_tx_send_byte_la;
byte uart_tx_byte_la;


assign led114 = led_full_la;
assign uart_tx_send_byte = uart_tx_send_byte_la;
assign uart_tx_byte = uart_tx_byte_la;

uart_rx 
  #(.CLKS_PER_BIT(UART_CLKS_PER_BIT))
	uart_rx0
  (
   .i_Clock(clock50mhz),
   .i_Rx_Serial(uart_rx_pin),
   .o_Rx_DV(uart_rx_received),
   .o_Rx_Byte(uart_rx_byte)
   );
	
uart_tx 
  #(.CLKS_PER_BIT(UART_CLKS_PER_BIT))
   uart_tx0
  (
   .i_Clock(clock50mhz),
   .i_Tx_DV(uart_tx_send_byte),
   .i_Tx_Byte(uart_tx_byte), 
   .o_Tx_Active(uart_tx_active),
   .o_Tx_Serial(uart_tx_pin),
	.o_Tx_Done()
   );
	
signal_timer #(.CLOCKS_PER_TICK(CLOCKS_PER_TICK_1MS))
	signal_timer_1ms(
	.clock(clock50mhz),
	.signal_out(signal_1ms)
	);
	
signal_timer #(.CLOCKS_PER_TICK(CLOCKS_PER_TICK_1US))
	signal_timer_1us(
	.clock(clock50mhz),
	.signal_out(signal_1us)
	);
	
uart_rx_controller #(.TIMEOUT_MS(500))
	uart_rx_controller0(
	.clock(clock50mhz),
	.uart_rx_received(uart_rx_received),
	.uart_rx_byte(uart_rx_byte),
	.dev_command_started(dev_command_started),
	.dev_command_processing(dev_command_processing),
	.dev_command(dev_command),
	.dev_busy(dev_busy),
	.dev_command_data_signal(dev_command_data_signal),
	.dev_data(dev_data),
	.signal_1ms(signal_1ms)
	);
	
bit write_data4_strobe;
bit read_data4_strobe;
bit[8:0] data4_count;

bit response_start_write = 0;
bit response_data_empty = 0;
bit response_data_strobe = 0;
bit response_data_req;
byte response_data;
	
//2 66 - clk
//3 67 - cmd
//4 68 - D0
//5 69 - D1
//6 70 - D2
//7 71 - D3

logic_analyzer_controller_200mhz_serial48 logic_analyzer_controller0(
		.clock(clock50mhz),
		.clock200mhz(clock200mhz),
		//Командный интерфейс
		.dev_command_started(dev_command_started_la),
		.dev_command_processing(dev_command_processing_la),
		.dev_command(dev_command[4:0]),
		.dev_busy(dev_busy_la),
		.dev_command_data_signal(dev_command_data_signal_la),
		.dev_data(dev_data),
		
		//uart out
		.uart_tx_send_byte(uart_tx_send_byte_la),
		.uart_tx_byte(uart_tx_byte_la),
		.uart_tx_active(uart_tx_active),
		
		//led
		.led_full(led_full_la),
		
		.logic_clock(sd_clock),
		.logic_serial(sd_cmd)
		);
/*		
logic_analyzer_controller_quadspi logic_analyzer_controller0(
		.clock(clock50mhz),
		.clock200mhz(clock200mhz),
		//Командный интерфейс
		.dev_command_started(dev_command_started_la),
		.dev_command_processing(dev_command_processing_la),
		.dev_command(dev_command[4:0]),
		.dev_busy(dev_busy_la),
		.dev_command_data_signal(dev_command_data_signal_la),
		.dev_data(dev_data),
		
		//uart out
		.uart_tx_send_byte(uart_tx_send_byte_la),
		.uart_tx_byte(uart_tx_byte_la),
		.uart_tx_active(uart_tx_active),
		
		//led
		.led_full(led_full_la),
		
		//Данные, которые мы анализируем
		.logic_clock(sd_clock),
		.logic_data(sd_data),
		
		.read_strobe(read_data4_strobe),
		.data_count(data4_count)
		);
*/
sdio_slave sdio_slave0(
	.clock(clock200mhz),
	.sd_clock(sd_clock),
	.sd_serial(sd_cmd),
	.sd_data(sd_data),
	
	.data4_count(data4_count),
	.write_data4_strobe(write_data4_strobe),
	.read_data4_strobe(read_data4_strobe),
	
	.response_start_write(response_start_write),
	.response_data_empty(response_data_empty),
	.response_data_strobe(response_data_strobe),
	.response_data_req(response_data_req),
	.response_data(response_data)
	
);

bit[2:0] dev_command_top;
assign dev_command_top = dev_command[7:5];
		
always_comb
begin
	dev_command_started_la = 0;
	dev_command_processing_la = 0;
	dev_command_data_signal_la = 0;
	
	dev_busy = dev_busy_la;
			
	case(dev_command_top)
	3'h2:
		begin
			dev_command_started_la = dev_command_started;
			dev_command_processing_la = dev_command_processing;
			dev_command_data_signal_la = dev_command_data_signal;
		end
	default:;
	endcase
end

always_ff @(posedge clock200mhz)
begin
	if(write_data4_strobe)
		led110 <= 1'd1;
end


//Временный код, чтобы передать данные.
type_data4_count write_count = 0;
always @(posedge clock200mhz)
begin

	response_start_write <= 0;
	response_data_strobe <= 0;
	if(write_data4_strobe)
	begin
		write_count <= data4_count;
		response_start_write <= 1'd1;
		response_data_empty <= 0;
	end
	
	if(response_data_req)
	begin
		if(write_count>0)
		begin
			response_data <= write_count[7:0]+8'h35;
			response_data_strobe <= 1'd1;
			write_count <= write_count-1'd1;
		end
		else
		begin
			response_data_empty <= 1'd1;
		end
	end

end

endmodule
