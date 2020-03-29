/*
 * Author:	Dmitriy 'Balmer' Poskryakov
 * Created:	2020
 * License: MIT License
*/

/*
Принимает на вход данные по байтам.
Отправляет их по sd_data четырем проводам.
Вначале пишет 0 как start bit
В конце пишет crc16 и 1 как end bit.
Естественно на линиях всегда 1 пока она свободна.
*/
module sd_response_stream_dat(
	input bit clock,
	
	input bit start_write, //Устанавливается на один такт, после чего запускается процедура передачи данных
	
	output bit data_req, //Требуется ещё один байт данных. Не позже, чем через 2 такта должен подняться сигнал data_strobe.
	input bit data_empty, //Данных больше нет, переходим к отсылке CRC16
	input bit data_strobe, //На 1 такт включается, когда в data корректные данные. Они должны быть корректны до окончания  передачи.
	input byte data,//Данные которые мы посылаем, должны быть валидны когда data_strobe==1
	
	input bit sd_clock, //Передаем бит, когда clock falling
	output bit[3:0] sd_data, //Пин, через который передаются данные
	output bit write_enabled, //Пока передаются данные write_enabled==1 (переключение inout получается уровнем выше)
	output bit read_disabled
);

initial sd_data = 4'b1111;
initial write_enabled = 0;
initial read_disabled = 0;

bit sd_clock2 = 0;
bit sd_clock3 = 0;

bit is_falling_clock;
assign is_falling_clock = sd_clock3==1'b1 && sd_clock2==1'b0;

bit crc16_clear = 1;
assign crc16_clear = start_write;
bit crc16_enable = 0; //только если enable==1 производим обработку
bit[3:0] crc16_in; //Биты данных который мы обрабатываем
bit[15:0] crc16[4];

sd_crc16 crc16_0(
	.clock(clock),
	.clear(crc16_clear),
	.enable(crc16_enable),
	.in(crc16_in[0]), 
	.crc(crc16[0]));
	
sd_crc16 crc16_1(
	.clock(clock),
	.clear(crc16_clear),
	.enable(crc16_enable),
	.in(crc16_in[1]), 
	.crc(crc16[1]));

sd_crc16 crc16_2(
	.clock(clock),
	.clear(crc16_clear),
	.enable(crc16_enable),
	.in(crc16_in[2]), 
	.crc(crc16[2]));
	
sd_crc16 crc16_3(
	.clock(clock),
	.clear(crc16_clear),
	.enable(crc16_enable),
	.in(crc16_in[3]), 
	.crc(crc16[3]));

bit[2:0] wait_before_write = 0;
bit[1:0] wait_after_write = 0;

typedef enum bit [3:0] {
	//В текущий момент передачи нет.
	SD_STOP = 4'h0,

	//Пишем в sd_data нули
	SD_START_ZERO = 4'h1,
	SD_START_ZERO2 = 4'h6,
	
	//Пишем старшую часть битов в байте.
	SD_WRITE_7_4_BITS = 4'h2,
	//Пишем младшую часть битов в байте.
	SD_WRITE_3_0_BITS = 4'h3,
	
	SD_WRITE_CRC = 4'h4,
	
	//Пишем в sd_data единицы и заканчиваем передачу.
	SD_END_ONE = 4'h5
	
} SD_COMMANDS;

SD_COMMANDS command = SD_STOP;

byte data_stored;
bit[3:0] data_prev_stored;

bit[3:0] crc_bit;

always @(posedge clock)
begin
	sd_clock2 <= sd_clock;
	sd_clock3 <= sd_clock2;
	
	crc16_enable <= 0;
	data_req <= 0;
		
	if(data_strobe)
		data_stored <= data;
	
	if(start_write)
	begin
		data_req <= 1'd1;
		read_disabled <= 1'd1;
		command <= SD_START_ZERO;
		wait_before_write <= 3'd7;
		wait_after_write <= 0;
	end
	else
	if(is_falling_clock)
	begin
		if(wait_before_write>0)
		begin
			wait_before_write <= wait_before_write-1'd1;
			if(wait_before_write==3'd1)
				write_enabled <= 1'd1;
		end
		else
		case(command)
		default: ;
		SD_STOP: begin
		end
		SD_START_ZERO : begin
			sd_data <= 4'd0;
			command <= SD_WRITE_7_4_BITS;
			//command <= SD_START_ZERO2;
		end
		
		SD_START_ZERO2 : begin
			sd_data <= 4'd0;
			command <= SD_WRITE_7_4_BITS;
		end
		
		SD_WRITE_7_4_BITS : begin
			sd_data <= data_stored[7:4];
			data_prev_stored <= data_stored[3:0];
			command <= SD_WRITE_3_0_BITS;
			
			crc16_in <= data_stored[7:4];
			crc16_enable <= 1'd1;
			
			data_req <= 1'd1;
		end
		SD_WRITE_3_0_BITS : begin
			sd_data <= data_prev_stored[3:0];
			crc16_in <= data_prev_stored[3:0];
			crc16_enable <= 1'd1;
			
			if(data_empty)
			begin
				crc_bit <= 4'd15;
				command <= SD_WRITE_CRC;
			end
			else
				command <= SD_WRITE_7_4_BITS;
		end
		
		SD_WRITE_CRC : begin
			sd_data <= {crc16[3][crc_bit], crc16[2][crc_bit], crc16[1][crc_bit], crc16[0][crc_bit]};
			
			if(crc_bit>0)
				crc_bit <= crc_bit-1'd1;
			else
				command <= SD_END_ONE;
		end
		
		SD_END_ONE: begin
			sd_data <= 4'b1111;
			command <= SD_STOP;
			
			wait_after_write <= 2'd3;
		end
	
		endcase
		
		if(wait_after_write>0)
		begin
			wait_after_write <= wait_after_write-1'd1;
			
			if(wait_after_write==2'd2)
				write_enabled <= 0;
			if(wait_after_write==2'd1)
				read_disabled <= 0;
		end
	end

end

endmodule
