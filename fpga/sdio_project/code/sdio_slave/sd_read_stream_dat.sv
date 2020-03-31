/*
 * Author:	Dmitriy 'Balmer' Poskryakov
 * Created:	2020
 * License: MIT License
*/

module sd_read_stream_dat(
	input bit clock,
	input bit sd_clock,
	input bit[3:0] sd_data,
	
	input bit read_strobe, //Когда начинать сэмплирование (устанавливается на 1 такт)
	input bit[8:0] data_count, //Количество байт, которые надо прочитать
	
	output bit write_byte_strobe, //Получили байт по SD протоколу
	output byte byte_out, //Полученный байт
	output bit write_all_strobe, //Все данные получены (устанавливается на 1 такт)
	output bit crc_ok //Читать в тот момент, когда write_all_strobe==1
);

bit[8:0] data_count_buf; //Количество байт, которые надо прочитать
bit[3:0] crc_read_idx; //После того, как прочитали данные - читаем 16 бит CRC и сравниваем с посчитанным
bit full_byte; //Устанавливается, если прочитан полный байт

bit sd_clock2 = 0;
bit sd_clock3 = 0;

bit[3:0] sd_data2 = 0;
bit[3:0] sd_data_prev = 0;

bit is_rising_clock;
assign is_rising_clock = sd_clock3==1'b0 && sd_clock2==1'b1;

bit start_word_capture = 0;
bit start_flag;
assign start_flag = data_count_buf>0 && sd_data_prev==4'b1111 && sd_data2==0 && start_word_capture==0;

bit read_data_complete;

bit crc16_clear = 1;
assign crc16_clear = read_strobe;
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

	
always_ff @(posedge clock)
begin
	sd_clock2 <= sd_clock;
	sd_clock3 <= sd_clock2;
	sd_data2 <= sd_data;
	write_byte_strobe <= 0;
	write_all_strobe <= 0;
	crc16_enable <= 0;
	
	if(read_strobe)
	begin
		data_count_buf <= data_count;
		crc_read_idx <= 4'hF;
		full_byte <= 0;
		start_word_capture <= 0;
		crc_ok <= 1'd1;
		
		read_data_complete <= 0;
	end
	
	if(is_rising_clock)
	begin
		sd_data_prev <= sd_data2;
		
		if(start_flag)
			start_word_capture <= 1'd1;
		
		if(start_word_capture)
		begin
			full_byte <= !full_byte;
			crc16_in <= sd_data2;
			crc16_enable <= !read_data_complete;
		
			if(full_byte && !read_data_complete)
			begin
				byte_out[7:4] <= crc16_in;
				byte_out[3:0] <= sd_data2;
				write_byte_strobe <= 1'd1;
				data_count_buf <= data_count_buf-1'd1;
				
				if(data_count_buf==9'd1)
					read_data_complete <= 1'd1;
			end
			
			if(read_data_complete)
			begin
				if( sd_data2[0]!=crc16[0][crc_read_idx]
				 || sd_data2[1]!=crc16[1][crc_read_idx]
				 || sd_data2[2]!=crc16[2][crc_read_idx]
				 || sd_data2[3]!=crc16[3][crc_read_idx]
				  )
					crc_ok <= 0;
					
				crc_read_idx <= crc_read_idx-1'd1;
				if(crc_read_idx==0)
				begin
					write_all_strobe <= 1'd1;
					start_word_capture<=0;
				end
			end
		end
	end
end


endmodule
