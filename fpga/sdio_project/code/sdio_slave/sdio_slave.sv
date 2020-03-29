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
	
	//Пока пусть в таком виде будет command interface, потом облагородим
	
	//Данные прочитанные из sdio command line
	output bit[37:0] read_data,
	output bit read_data_strobe,
	output bit read_error,
	
	//Данные, которые следует отослать по sdio command line
	input bit[37:0] write_data,
	input bit write_data_strobe,

	//Количество данных, которые требуется передать.
	//Пока это временный вариант.
	input bit write_data4_strobe,
	input bit[8:0] write_data4_count,
	
	output bit read_disabled, //Пока 1 - нельзя передавать команды
	output bit read_disabled4 //Пока 1 - нельзя передавать данные
);

bit write_enabled;
bit sd_serial_out;
assign sd_serial = write_enabled?sd_serial_out:1'bz;

bit write_enabled4;
bit[3:0] sd_data_out;
assign sd_data = write_enabled4?sd_data_out:4'bz;


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

bit[8:0] write_count = 0;
bit start_write = 0;
bit data_empty;
bit data_strobe;
bit data_req;
byte data;

sd_response_stream_dat response_dat(
	.clock(clock),
	
	.start_write(start_write),
	
	.data_req(data_req),
	.data_empty(data_empty),
	.data_strobe(data_strobe),
	.data(data),
	
	.sd_clock(sd_clock), //Передаем бит, когда clock falling
	.sd_data(sd_data_out), //Пин, через который передаются данные
	.write_enabled(write_enabled4), //Пока передаются данные write_enabled==1 (переключение inout получается уровнем выше)
	.read_disabled(read_disabled4)
);

//Временный код, чтобы передать данные.
always @(posedge clock)
begin
	start_write <= 0;
	data_strobe <= 0;
	if(write_data4_strobe)
	begin
		write_count <= write_data4_count;
		start_write <= 1'd1;
		data_empty <= 0;
	end
	
	if(data_req)
	begin
		if(write_count>0)
		begin
			data <= write_count[7:0]+8'h35;
			data_strobe <= 1'd1;
			write_count <= write_count-1'd1;
		end
		else
		begin
			data_empty <= 1'd1;
		end
	end
	
end

endmodule
