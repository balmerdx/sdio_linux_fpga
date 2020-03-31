/*
 * Author:	Dmitriy 'Balmer' Poskryakov
 * Created:	2020
 * License: MIT License
*/

module sdio_slave(
	input bit clock,
	input bit sd_clock,
	inout wire sd_serial,
	inout wire[3:0] sd_data,
	
	//Количество данных, которые требуется передать или принять
	output type_data4_count data4_count,
	output bit write_data4_strobe,
	output bit read_data4_strobe,

	//Интерфейс для отсылки данных по dat 4 линиям
	//После того, как пришел write_data4_strobe надо на 1 такт поднять response_start_write
	//и тем начать передачу
	// response_data_req - Поднимается на 1 такт, когда требуюется следующий байт response_data.
	// так как он требуется через достаточно продолжительное время, то задержка в 2 такта допустима
	// response_data_strobe выставляется на 1 такт, чтобы указать, что данные готовы (в ответ на response_data_req)
	// response_data_empty выставляется, если данных больше нет (в ответ на response_data_req)
	input bit response_start_write, 
	input bit response_data_empty,
	input bit response_data_strobe,
	output bit response_data_req, 
	input byte response_data,
	
	//Интерфейс для приёма данных по dat 4 линиям
	//read_byte_strobe прочитался байт
	//read_all_strobe - прочитались все data4_count байт
	//read_byte - байт который прочитался
	//read_crc_ok4 - проверка CRC подтвердила, что байты прочитались корректно (сморреть когда read_all_strobe==1)
	output bit read_byte_strobe,
	output bit read_all_strobe,
	output byte read_byte,
	output bit read_crc_ok4
);

bit write_enabled;
bit sd_serial_out;
assign sd_serial = write_enabled?sd_serial_out:1'bz;

bit write_enabled4;
bit[3:0] sd_data_out;
assign sd_data = write_enabled4?sd_data_out:4'bz;

//Данные прочитанные из sdio command line
bit[37:0] read_data;
bit read_data_strobe;
bit read_error;

//Данные, которые следует отослать по sdio command line
bit[37:0] write_data;
bit write_data_strobe;

bit read_disabled; //Пока 1 - нельзя передавать команды
bit read_disabled4; //Пока 1 - нельзя передавать данные

bit start_send_crc_status = 0;
bit crc_status;


sd_response_stream response(
	.clock(clock),
	.data(write_data),
	.data_strobe(write_data_strobe),
	.sd_clock(sd_clock),
	.sd_serial(sd_serial_out),
	.write_enabled(write_enabled),
	.read_disabled(read_disabled)
);

sd_read_stream read(
	.clock(clock),
	.sd_clock(sd_clock),
	.sd_serial(sd_serial),
	.read_enabled(~read_disabled),
	.data(read_data),
	.data_strobe(read_data_strobe),
	.read_error(read_error)
);

sd_response_stream_dat response_dat(
	.clock(clock),
	
	.start_write(response_start_write),
	
	.data_req(response_data_req),
	.data_empty(response_data_empty),
	.data_strobe(response_data_strobe),
	.data(response_data),
	
	.start_send_crc_status(start_send_crc_status),
	.crc_status(crc_status),
	
	.sd_clock(sd_clock), //Передаем бит, когда clock falling
	.sd_data(sd_data_out), //Пин, через который передаются данные
	.write_enabled(write_enabled4), //Пока передаются данные write_enabled==1 (переключение inout получается уровнем выше)
	.read_disabled(read_disabled4)
);

sd_read_stream_dat read_dat(
	.clock(clock),
	.sd_clock(sd_clock),
	.sd_data(sd_data),
	
	.read_strobe(read_data4_strobe),
	.data_count(data4_count),
	
	.write_byte_strobe(read_byte_strobe),
	.byte_out(read_byte),
	.write_all_strobe(read_all_strobe),
	.crc_ok(read_crc_ok4)
);


sdio_commands_processor sdio_commands(
	.clock(clock),
	
	.read_data(read_data),
	.read_data_strobe(read_data_strobe),
	.read_error(read_error),
	
	.write_data(write_data),
	.write_data_strobe(write_data_strobe),
	
	.write_data4_strobe(write_data4_strobe),
	.read_data4_strobe(read_data4_strobe),
	.data4_count(data4_count),
	
	.send_command_in_progress(read_disabled),
	.send_data_in_progress(read_disabled4)
);


//Временный код, чтобы передать данные.
always @(posedge clock)
begin
	start_send_crc_status <= 0;

	//Передаём ответ, что мы приняли данные
	if(read_all_strobe)
	begin
		start_send_crc_status <= 1'd1;
		crc_status <= read_crc_ok4;
	end
end

endmodule
