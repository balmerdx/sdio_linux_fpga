/*
 * Author:	Dmitriy 'Balmer' Poskryakov
 * Created:	2020
 * License: MIT License
*/

typedef enum bit [4:0] {
	RX_STATE_IDLE = 5'h0,
	RX_STATE_WAIT_COMMAND_BYTE,//1
	RX_STATE_COMMAND_BYTE,//2
	RX_STATE_WAIT_SIZE_BYTE,//3
	RX_STATE_SIZE_BYTE,//4
	RX_STATE_CHECK_DATA_SIZE,//5
	RX_STATE_START_EXECUTE_COMMAND,//6
	RX_STATE_WAIT_NOT_BUSY,//7
	RX_STATE_WAIT_DATA_BYTE,//8
	RX_STATE_DATA_BYTE,//9
	RX_STATE_BEFORE_IDLE //10
} RX_STATE;


module uart_rx_controller
	//Через такое количество времени данные из буфера будут очищенны.
	#(parameter TIMEOUT_MS = 10)
	(
	input clock,
	input bit uart_rx_received,
	input byte uart_rx_byte,

	//Команда, пересылаемая на устройство. Может пересылаться медленно.
	//Только один clock при начале пересылки команды на устройство
	output bit dev_command_started,
	//Все время, пока выполняется команда dev_command_processing==1
	output bit dev_command_processing,
	//Байт команды, валиден все время, пока идет передача команды на устройство
	output byte dev_command,
	//Пока dev_busy==1 - не читать следующего байта из fifo
	input bit dev_busy,
	//dev_command_data_signal==1 если валидные данные в dev_data
	//Данные пересылаются медленно.
	//Сначала проверяется, что dev_busy==0.
	//Запускается запрос в FIFO.
	//После ожидания два такта - выставляется сигнал dev_command_data_signal.
	output bit dev_command_data_signal,
	output byte dev_data,
	
	//Каждую милисекунду на 1 такт этот сигнал становится равным 1
	input bit signal_1ms
	);

localparam ADDR_WIDTH = 9;

initial dev_command_started = 0;
initial dev_command_processing= 0;
initial dev_command_data_signal = 0;
	
bit fifo_clear = 0;
bit fifo_write_request;
bit fifo_read_request = 0;
bit fifo_empty;
bit fifo_full;
bit[ADDR_WIDTH-1:0] fifo_stored_bytes;
byte fifo_out_data;

RX_STATE rx_state = RX_STATE_IDLE;
byte size_byte;
byte current_data_byte;

bit [$clog2(TIMEOUT_MS):0] timeout_ms_counter = 0;


assign dev_data = fifo_out_data;
assign fifo_write_request = uart_rx_received;

`ifdef HARDWARE_DEVICE

uart_rx_fifo uart_rx_fifo0(
	.clock(clock),
	.data(uart_rx_byte),
	.rdreq(fifo_read_request),
	.sclr(fifo_clear),
	.wrreq(fifo_write_request),
	.empty(fifo_empty),
	.full(fifo_full),
	.q(fifo_out_data),
	.usedw(fifo_stored_bytes));
	
`else

fifo #(.ADDR_WIDTH(ADDR_WIDTH))
	uart_rx_fifo0(
	.clock(clock),
	.data_in(uart_rx_byte),
	.rdreq(fifo_read_request),
	.syncronous_clear(fifo_clear),
	.wrreq(fifo_write_request),
	.empty(fifo_empty),
	.full(fifo_full),
	.data_out(fifo_out_data),
	.usedw(fifo_stored_bytes)
	);

`endif

always_ff @(posedge clock)
begin
	if(dev_command_started)
		dev_command_started <= 0;
		
	if(dev_command_data_signal)
		dev_command_data_signal <= 0;
		
	if(fifo_read_request)
		fifo_read_request <= 0;
		
	if(fifo_clear)
		fifo_clear <= 0;
		
	if(uart_rx_received)
		timeout_ms_counter <= 0;
		
	if(signal_1ms)
	begin
		timeout_ms_counter <= timeout_ms_counter+1'd1;
		if(timeout_ms_counter>=TIMEOUT_MS && !dev_command_processing)
		begin
			fifo_clear <= 1;
			rx_state <= RX_STATE_BEFORE_IDLE;
			timeout_ms_counter <= 0;
		end
	end

	case(rx_state)
		default : begin
		end
		
		RX_STATE_BEFORE_IDLE : begin
			rx_state <= RX_STATE_IDLE;
		end

		RX_STATE_IDLE: begin
			if(!fifo_empty)
			begin
				rx_state <= RX_STATE_WAIT_COMMAND_BYTE;
				fifo_read_request <= 1;
			end
			dev_command_processing <= 0;
			timeout_ms_counter <= 0;
		end
		
		RX_STATE_WAIT_COMMAND_BYTE : begin
			//Два такта проходит от fifo_read_request <=1 до получения данных в fifo_out_data
			rx_state <= RX_STATE_COMMAND_BYTE;
		end
		
		RX_STATE_COMMAND_BYTE : begin
			dev_command <= fifo_out_data;
			if(!fifo_empty)
			begin
				rx_state <= RX_STATE_WAIT_SIZE_BYTE;
				fifo_read_request <= 1;
			end
		end
		
		RX_STATE_WAIT_SIZE_BYTE : begin
			rx_state <= RX_STATE_SIZE_BYTE;
		end
		
		RX_STATE_SIZE_BYTE : begin
			size_byte <= fifo_out_data;
			rx_state <= RX_STATE_CHECK_DATA_SIZE;
		end
		
		RX_STATE_CHECK_DATA_SIZE : begin
			if(ADDR_WIDTH'(size_byte) <= fifo_stored_bytes && !dev_busy)
			begin
				rx_state <= RX_STATE_START_EXECUTE_COMMAND;
			end
		end
		
		RX_STATE_START_EXECUTE_COMMAND: begin
			dev_command_started <= 1;
			dev_command_processing <= 1;
			current_data_byte <= 0;
			
			if(size_byte==0)
				rx_state <= RX_STATE_IDLE;
			else
				rx_state <= RX_STATE_WAIT_NOT_BUSY;
			
		end
		
		RX_STATE_WAIT_NOT_BUSY: begin
			if(!dev_busy)
			begin
				fifo_read_request <= 1;
				rx_state <= RX_STATE_WAIT_DATA_BYTE;
			end
		end
		
		RX_STATE_WAIT_DATA_BYTE: begin
			fifo_read_request <= 0;
			rx_state <= RX_STATE_DATA_BYTE;
			dev_command_data_signal <= 1;
		end
		
		
		RX_STATE_DATA_BYTE : begin
			dev_command_data_signal <= 0;
			timeout_ms_counter <= 0;
			if(current_data_byte+1==size_byte)
			begin
				rx_state <= RX_STATE_IDLE;
			end
			else
			begin
				current_data_byte <= current_data_byte+1'd1;
				rx_state <= RX_STATE_WAIT_NOT_BUSY;
			end
		end
	endcase
	
end
	
endmodule
