/*
 * Author:	Dmitriy 'Balmer' Poskryakov
 * Created:	2020
 * License: MIT License
*/

/*
	По умолчанию на sd_serial 1
	Если sd_serial 1->0, то началась команда.
	Все команды 48 бит. 38 бит полезной нагрузки, остальное - CRC и начальные 2 бита.
	Первый бит всегда 0.
	Второй бит всегда 1. Если второй бит 0, то игнорируем последующие 48 байт.
*/

module sd_read_stream(
	input bit clock,
	input bit sd_clock,
	input bit sd_serial,
	input bit read_enabled,
	output bit[37:0] data,//Полезная часть данных. Валидны, когда data_strobe==1
	output bit data_strobe, //На 1 такт включается, когда в data корректные данные.
	output bit read_error //Если команда прията, но crc не совпадает (или другие обязательные биты),
								 //то на 1 такт поднимается этот бит
);

//State machine для отсылки байтиков
typedef enum bit [1:0] {
	ST_IDLE = 2'h0,
	ST_READ_BITS = 2'h1,
	ST_CHECK_CRC = 2'h2
} STATE;

STATE state = ST_IDLE;

bit sd_clock2 = 0;
bit sd_clock3 = 0;
bit sd_serial2 = 0;
bit sd_serial_prev = 0;

bit[5:0] current_bit = 0;

bit is_rising_clock;
assign is_rising_clock = sd_clock3==1'b0 && sd_clock2==1'b1;

bit [47:0] data48;
assign data = data48[45:8];

bit crc7_clear;
bit crc7_enable = 0;
bit crc7_bit;
bit[6:0] crc7;

sd_crc7 crc7m(
	.clock(clock),
	.clear(crc7_clear),
	.enable(crc7_enable), //только если enable==1 производим обработку
	.in_bit(crc7_bit), //Бит данных который мы обрабатываем
	.crc(crc7));
	
bit crc_ok;
bit check_ok;
assign crc_ok = crc7==data48[7:1];
assign check_ok = crc_ok && data48[46]==1'd1 && data48[0]==1'd1;
	
always_ff @(posedge clock)
begin
	sd_clock2 <= sd_clock;
	sd_clock3 <= sd_clock2;
	sd_serial2 <= sd_serial;
	data_strobe <= 0;
	read_error <= 0;

	if(crc7_enable)
		crc7_enable <= 0;
	if(is_rising_clock)
		sd_serial_prev <= sd_serial2; //st_serial2 - это наше текущее значение, вычитанное при falling
		
	if(read_enabled==0)
	begin
		state <= ST_IDLE;
		crc7_clear <= 1'b1;
	end
	else
	case(state)
	default:
		state <= ST_IDLE;
	ST_IDLE:
		if(is_rising_clock && sd_serial_prev==1'b1 && sd_serial2==0)
		begin
			current_bit <= 46;
			data48[47] <= 1'b0;
			crc7_bit <= 1'b0;
			crc7_clear <= 0;
			crc7_enable <= 1'b1;
			state <= ST_READ_BITS;
		end
		else
		begin
			crc7_clear <= 1'b1;
		end
	
	ST_READ_BITS:
		if(is_rising_clock)
		begin
			data48[current_bit] <= sd_serial2;
			crc7_bit <= sd_serial2;
			
			if(current_bit>=6'd8)
				crc7_enable <= 1'b1;
			
			if(current_bit>0)
				current_bit <= current_bit-1'b1;
			else
				state <= ST_CHECK_CRC;
		end
	
	ST_CHECK_CRC:
		begin
			if(check_ok)
				data_strobe <= 1'd1;
			else
				read_error <= 1'd1;
			state <= ST_IDLE;
		end
	endcase
end

endmodule
