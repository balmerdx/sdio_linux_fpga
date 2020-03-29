module logic_analyzer_controller_quadspi(
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
		input bit logic_clock,
		input bit[3:0] logic_data,
		
		input bit read_strobe, //Когда начинать сэмплирование
		input bit[8:0] data_count //Количество байт, которые надо записать
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

bit logic_clock2 = 0;
bit logic_clock3 = 0;

bit[3:0] logic_data2 = 0;
bit[3:0] logic_data_prev = 0;

LA_SM la_sm = LA_SM_IDLE;

assign led_full = fifo_full;

localparam bit[10:0] data_count_x2_init = 11'h600;
//bit[10:0] data_count_x2 = 0;//Количество полубайт, которые надо записать
bit[10:0] data_count_x2 = data_count_x2_init;

	
logic_alanyser_fifo8_async logic_analyzer_fifo0(
	.data(fifo_in),
	.rdclk(clock),
	.rdreq(fifo_read_req),
	.wrclk(clock200mhz),
	.wrreq(fifo_write_req),
	.q(fifo_out),
	.rdempty(fifo_empty),
	.wrfull(fifo_full));
	
bit start_word_capture = 0;

//bit is_falling_clock;
bit is_rising_clock;
//assign is_falling_clock = logic_clock3==1'b1 && logic_clock2==1'b0;
assign is_rising_clock = logic_clock3==1'b0 && logic_clock2==1'b1;

bit start_flag;
assign start_flag = data_count_x2>0 && logic_data_prev==4'b1111 && logic_data2==0 && start_word_capture==0;
	
always_ff @(posedge clock200mhz)
begin
	logic_clock2 <= logic_clock;
	logic_clock3 <= logic_clock2;
	logic_data2 <= logic_data;
	fifo_write_req <= 0;
	
	if(read_strobe)
	begin
		//Временно data_count_x2 <= {1'd0, data_count, 1'd0}+10'h20;//Ещё пару байт в конце отсэмплируем
	end
	
	if(is_rising_clock)
	begin
		//logic_data2 - это наше текущее значение, вычитанное при falling
		logic_data_prev <= logic_data2;
		
		if(start_flag)
		begin
			start_word_capture <= 1'b1;
		end
		
		if(start_word_capture || start_flag)
		begin
			if(data_count_x2[0])
				fifo_in[7:4] <= logic_data2;
			else
			begin
				fifo_in[3:0] <= logic_data2;
				fifo_write_req <= 1'b1;
			end
			
			if(data_count_x2>0)
			begin
				data_count_x2 <= data_count_x2-1'd1;
			end
			else
			begin
				start_word_capture <= 0;
				data_count_x2 <= data_count_x2_init; //Временно
			end
		end
	end
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
