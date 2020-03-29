/*
 * Author:	Dmitriy 'Balmer' Poskryakov
 * Created:	2020
 * License: MIT License
*/

/*
Принимает на вход команду без crc и начальных конечных битов.
На выход выдает последовательность бит.
Bit 47 всегда 0 (start bit)
Бит 46 всегда 0 (т.к. это ответ)
Биты 7-1 CRC7
Бит 0 всегда 1 (end bit)

clock - у нас будет 200 МГц.
sd_clock - у нас 50 МГц либо меньше

Так как данные читаются по sd_clock falling,
то писать их надо примерно по sd_clock rising.
Можно попытаться писать по sd_clock falling + несколько тактов задержки.
Собственно говоря тактов задержи и так более чем достаточно.
*/
module sd_response_stream(
	input bit clock,
	input bit[37:0] data,//Данные которые мы посылаем, должны быть валидны всё время, пока идёт отсылка
	input bit data_strobe, //На 1 такт включается, когда в data корректные данные. Они должны быть корректны до окончания  передачи.
	input bit sd_clock, //Передаем бит, когда clock falling
	output bit sd_serial, //Пин, через который передаются данные
	output bit write_enabled, //Пока передаются данные write_enabled==1 (переключение inout получается уровнем выше)
	output bit read_disabled
);

initial sd_serial = 1'd1;
initial write_enabled = 0;
initial read_disabled = 0;

bit sd_clock2 = 0;
bit sd_clock3 = 0;

bit is_falling_clock;
assign is_falling_clock = sd_clock3==1'b1 && sd_clock2==1'b0;

bit crc7_clear = 1;
assign crc7_clear = data_strobe;
bit crc7_enable = 0;
bit crc7_bit;
bit[6:0] crc7;

sd_crc7 crc7m(
	.clock(clock),
	.clear(crc7_clear),
	.enable(crc7_enable), //только если enable==1 производим обработку
	.in_bit(crc7_bit), //Бит данных который мы обрабатываем
	.crc(crc7));

bit[47:0] data48;
assign data48[45:8] = data;
assign data48[7:1] = crc7;
assign data48[47] = 1'b0;
assign data48[46] = 1'b0;
assign data48[0] = 1'b1;

bit[5:0] counter = 6'h3f;

bit[2:0] wait_before_write = 0;
bit[1:0] wait_after_write = 0;

always @(posedge clock)
begin
	sd_clock2 <= sd_clock;
	sd_clock3 <= sd_clock2;
	
	if(crc7_enable)
		crc7_enable <= 0;
	
	if(data_strobe)
	begin
		counter <= 6'd47;
		wait_before_write <= 3'd7;
		sd_serial <= 1'd1;
		read_disabled <= 1'd1;
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
		begin
			if(counter<6'd48)
			begin
				sd_serial <= data48[counter];
				if(counter>=6'd8)
				begin
					crc7_enable <= 1'd1;
					crc7_bit <= data48[counter];
				end
				
				if(counter==0)
					wait_after_write <= 2'd3;
					
				counter <= counter-1'd1;
			end
			
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
end

endmodule
