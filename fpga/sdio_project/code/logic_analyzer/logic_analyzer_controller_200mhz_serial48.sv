module logic_analyzer_controller_200mhz_serial48(
		input bit clock,
		input bit clock200mhz,
		//Командный интерфейс
		input bit dev_command_started,
		input bit dev_command_processing,
		input bit[4:0] dev_command,
		output bit dev_busy,
		input bit dev_command_data_signal,
		input byte dev_data,
		
		//uart out
		output bit uart_tx_send_byte,
		output byte uart_tx_byte,
		input bit uart_tx_active,
		
		//led
		output bit led_full,
		
		//Данные, которые мы анализируем
		//Все посылки по 48 бит
		//Начинаются с перехода logic_serial 1->0
		input bit logic_clock,
		input bit logic_serial
		);

typedef enum bit [4:0] {
	//Очищает FIFO
	//Начинает запись заново
	//В текущий момент не работает
	LA_CLEAR = 5'h0,
	
	//Читаем все данные из буфера
	//Состоит из блоков по 48 бит = 6 байт
	LA_READ_ALL = 5'h1
} LA_COMMANDS;

//State machine для отсылки байтиков
typedef enum bit [2:0] {
	LA_SM_IDLE = 3'h0,
	LA_SM_START_READ_WORD = 3'h1,
	LA_SM_WAIT_READ_WORD_OR_TX_START = 3'h2,
	LA_SM_WAIT_READ_WORD_OR_TX_START2 = 3'h3,
	LA_SM_WRITE_WORD = 3'h4
} LA_SM;
		
typedef bit [47:0] data_type;

initial dev_busy = 0;

data_type fifo_in;
data_type fifo_out;
bit fifo_full;
bit fifo_empty;
bit fifo_read_req = 0;
bit fifo_write_req = 0;

bit logic_clock2 = 0;
bit logic_clock3 = 0;
bit logic_serial2 = 0;
bit logic_serial_prev = 0;

LA_SM la_sm = LA_SM_IDLE;
bit [3:0] current_byte = 0;

assign led_full = fifo_full;
	
logic_analyzer_fifo_async logic_analyzer_fifo0(
	.data(fifo_in),
	.rdclk(clock),
	.rdreq(fifo_read_req),
	.wrclk(clock200mhz),
	.wrreq(fifo_write_req),
	.q(fifo_out),
	.rdempty(fifo_empty),
	.wrfull(fifo_full));
	
//bit3 67 - cmd когда он переходит с 1 в 0, значит началась команда,
//ещё много-много тактов вперёд надо сэмплировать.
bit[5:0] current_bit = 0;
bit start_word_capture = 0;

bit is_falling_clock;
bit is_rising_clock;
assign is_falling_clock = logic_clock3==1'b1 && logic_clock2==1'b0;
assign is_rising_clock = logic_clock3==1'b0 && logic_clock2==1'b1;
	
always_ff @(posedge clock200mhz)
begin
	logic_clock2 <= logic_clock;
	logic_clock3 <= logic_clock2;
	logic_serial2 <= logic_serial;
	fifo_write_req <= 0;
	
	if(is_rising_clock)
	begin
		//logic_serial2 - это наше текущее значение, вычитанное при falling
		logic_serial_prev <= logic_serial2;
		
		if(logic_serial_prev==1'b1 && logic_serial2==0 && start_word_capture==0)
		begin
			current_bit <= 46;
			fifo_in[47] <= 1'b0;
			start_word_capture <= 1'b1;
		end
		
		if(start_word_capture)
		begin
			fifo_in[current_bit] <= logic_serial2;
			if(current_bit>0)
			begin
				current_bit <= current_bit-1'b1;
			end
			else
			begin
				fifo_write_req <= 1'b1;
				start_word_capture <= 0;
			end
		end
	end
end

always_ff @(posedge clock)
begin
	if(fifo_read_req)
		fifo_read_req <= 0;
		
	if(uart_tx_send_byte)
		uart_tx_send_byte <= 0;
	
	if(dev_command_started)
	begin
		case(dev_command)
		LA_CLEAR:
			begin
			end
		LA_READ_ALL:
			begin
				la_sm <= LA_SM_START_READ_WORD;
			end
		endcase
	end

	case(la_sm)
	LA_SM_IDLE : ;
	LA_SM_START_READ_WORD:
		if(fifo_empty)
		begin
			la_sm <= LA_SM_IDLE;
		end
		else
		begin
			fifo_read_req <= 1;
			la_sm <= LA_SM_WAIT_READ_WORD_OR_TX_START;
			current_byte <= 0;
		end
		
	LA_SM_WAIT_READ_WORD_OR_TX_START: 
		la_sm <= LA_SM_WAIT_READ_WORD_OR_TX_START2;
		
	LA_SM_WAIT_READ_WORD_OR_TX_START2:
		la_sm <= LA_SM_WRITE_WORD;
	
	LA_SM_WRITE_WORD:
		if(!uart_tx_active)
		begin
			if(current_byte==6)
			begin
				current_byte <= 0;
				la_sm <= LA_SM_START_READ_WORD;
			end
			else
			begin
				uart_tx_byte <= fifo_out[8*current_byte +: 8];
				uart_tx_send_byte <= 1;
				current_byte <= current_byte+1'd1;
				la_sm <= LA_SM_WAIT_READ_WORD_OR_TX_START;
			end
		end
	endcase
end

endmodule
