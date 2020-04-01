module logic_analyzer_controller_bytecopy(
		input bit clock,
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
		
		//Данные, которые мы пишем
		input bit data_clock,
		input bit data_strobe,
		input byte data
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
		
initial dev_busy = 0;

byte fifo_in;
byte fifo_out;
bit fifo_full;
bit fifo_empty;
bit fifo_read_req = 0;
bit fifo_write_req = 0;

bit[3:0] logic_data2 = 0;
bit[3:0] logic_data_prev = 0;

LA_SM la_sm = LA_SM_IDLE;

assign led_full = fifo_full;
	
logic_alanyser_fifo8_async logic_analyzer_fifo0(
	.data(fifo_in),
	.rdclk(clock),
	.rdreq(fifo_read_req),
	.wrclk(data_clock),
	.wrreq(fifo_write_req),
	.q(fifo_out),
	.rdempty(fifo_empty),
	.wrfull(fifo_full));
	

always_ff @(posedge data_clock)
begin
	fifo_in <= data;
	fifo_write_req <= data_strobe;
end

always_ff @(posedge clock)
begin
	fifo_read_req <= 0;
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
			fifo_read_req <= 1'd1;
			la_sm <= LA_SM_WAIT_READ_WORD_OR_TX_START;
		end
		
	LA_SM_WAIT_READ_WORD_OR_TX_START: 
		la_sm <= LA_SM_WAIT_READ_WORD_OR_TX_START2;
		
	LA_SM_WAIT_READ_WORD_OR_TX_START2:
		la_sm <= LA_SM_WRITE_WORD;
	
	LA_SM_WRITE_WORD:
		if(!uart_tx_active)
		begin
			uart_tx_byte <= fifo_out;
			uart_tx_send_byte <= 1'd1;
			la_sm <= LA_SM_START_READ_WORD;
		end
	endcase
end

endmodule
