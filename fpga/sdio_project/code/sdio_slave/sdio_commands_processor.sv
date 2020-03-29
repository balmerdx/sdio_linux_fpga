/*
 * Author:	Dmitriy 'Balmer' Poskryakov
 * Created:	2020
 * License: MIT License
*/

module sdio_commands_processor(
	input bit clock,
	//Данные прочитанные из sdio command line
	input bit[37:0] read_data,
	input bit read_data_strobe,
	input bit read_error,
	
	//Данные, которые следует отослать по sdio command line
	output bit[37:0] write_data,
	output bit write_data_strobe,//Отослать 38 байт и CRC

	//Передача/прием данных по dat0-dat3
	output bit write_data4_strobe, //Данные надо отсылать на хост
	output bit read_data4_strobe,  //Данные надо принимать
	output bit[8:0] data4_count, //Количество данных, которые следует отослать или принять по dat0-dat3
	
	input bit send_command_in_progress, //В текущий момент передаётся команда
	input bit send_data_in_progress //В текущий момент данные отсылаются
);

initial write_data_strobe = 0;
initial write_data4_strobe = 0;

bit[5:0] read_command_index;
bit read_write_flag; //1- запись, 0 - чтение
bit[2:0] read_function_number;
//bit read_raw_flag;
bit[17:0] read_register_address;
bit[7:0] read_register_data;
bit[8:0] cmd53_count; //Количество данных, которые надо прочитать, или записать

assign read_command_index = read_data[37:32];
assign read_write_flag = read_data[31];
assign read_function_number = read_data[30:28];
//assign read_raw_flag = read_data[27];
assign read_register_address = read_data[25:9];
assign read_register_data = read_data[7:0];
assign cmd53_count = read_data[8:0];

//Битики Response Flags Bit специфичные для ответа CMD52
//bit 7 '0'= no error '1'= error
//The CRC check of the previous command failed.
bit COM_CRC_ERROR = 0;

//bit 6 '0'= no error '1'= error
//Command not legal for the card State.
bit ILLEGAL_COMMAND = 0;

//bit 5-4
//00=DIS 01=CMD 02=TRN 03=RFU
//DIS=Disabled: Initialize, Standby and Inactive States (card not selected)
//CMD=DAT lines free: 1. Command waiting (Notransaction suspended) 2. Command waiting (All CMD53 transactions suspended)
//3. Executing CMD52 in CMDState
//TRN=Transfer: Command executing with data transfer using DAT[0] or DAT[3:0] lines
bit[1:0] IO_CURRENT_STATE = 0;
//bit 3 '0'= no error '1'= error
//A general or an unknown error occurred during the operation.
bit GENERAL_ERROR = 0;

//Bit 1 '0'= no error '1'= error
//An invalid function number was requested
bit INVALID_FUNCTION_NUMBER = 0;

//bit 0 '0'= no error '1'= error
//ER: The command's argument was out of the allowed range for this card.
//EX: Out of range occurs during execution of CMD53.
bit OUT_OF_RANGE = 0;

bit [7:0] cmd52_response_flags_bit;
assign cmd52_response_flags_bit[7] = COM_CRC_ERROR;
assign cmd52_response_flags_bit[6] = ILLEGAL_COMMAND;
assign cmd52_response_flags_bit[5:4] = IO_CURRENT_STATE;
assign cmd52_response_flags_bit[3] = GENERAL_ERROR;
assign cmd52_response_flags_bit[2] = 0;
assign cmd52_response_flags_bit[1] = INVALID_FUNCTION_NUMBER;
assign cmd52_response_flags_bit[0] = OUT_OF_RANGE;

byte cmd52_response_reg_data = 0;

bit send_cmd52 = 0;
bit send_cmd53 = 0;

bit[3:0] wait_after_cmd = 0;
bit read_data4_strobe_after_cmd = 0;
bit write_data4_strobe_after_cmd = 0;

const bit[15:0] predefined_rca = 16'h2AB1;
bit[15:0] reg_rca = 0;//RCA register

bit[31:0] reg_card_status;//Card Status Register
assign reg_card_status[31] = OUT_OF_RANGE;
assign reg_card_status[30:24] = 0;
assign reg_card_status[23] = COM_CRC_ERROR;
assign reg_card_status[22] = ILLEGAL_COMMAND;
assign reg_card_status[21:20] = 0;
assign reg_card_status[19] = GENERAL_ERROR;
assign reg_card_status[18:13] = 0;
assign reg_card_status[12:9] = 4'd15; //CURRENT_STATE 
assign reg_card_status[8:0] = 0;

bit card_selected = 0;

bit [15:0] block_size = 0;

byte cis_array[0:63];
initial $readmemh("cis.mem", cis_array, 0);

bit[7:0] read_counter = 32;
bit read_empty = 0;

always @(posedge clock)
begin
	
	write_data_strobe <= 0;
	write_data4_strobe <= 0;
	read_data4_strobe <= 0;
	
	if(send_data_in_progress)
		IO_CURRENT_STATE <= 2'd2;
	else
	if(card_selected)
		IO_CURRENT_STATE <= 2'd1;
	else
		IO_CURRENT_STATE <= 2'd0;
		
	if(wait_after_cmd > 0)
		wait_after_cmd <= wait_after_cmd-1'd1;
		
	if(send_cmd52)
	begin
		send_cmd52 <= 0;
		
		write_data_strobe <= 1'd1;
		write_data[37:32] <= 6'd52;
		write_data[7:0] <= cmd52_response_reg_data;
		write_data[15:8] <= cmd52_response_flags_bit;
		INVALID_FUNCTION_NUMBER <= 0;
	end

	if(send_cmd53)
	begin
		send_cmd53 <= 0;
		write_data_strobe <= 1'd1;
		write_data <= 0;
		write_data[37:32] <= 6'd53;
		//Видимо здесь будет R5 ответ (аналогично CMD52)
		/*
		if(read_data4_strobe_after_cmd) //See 4.10.1 Card Status
			write_data[31:0] <= 32'hd00; //CURRENT_STATE==rcv=6, READY_FOR_DATA=1
		else
			write_data[31:0] <= 32'h900; //CURRENT_STATE==tran=4, READY_FOR_DATA=1
		*/
		write_data[7:0] <= cmd52_response_reg_data;
		write_data[15:8] <= cmd52_response_flags_bit;
		INVALID_FUNCTION_NUMBER <= 0;
	end
	
	if(wait_after_cmd==0 && !send_command_in_progress)
	begin
		if(read_data4_strobe_after_cmd)
		begin
			read_data4_strobe_after_cmd <= 0;
			read_data4_strobe <= 1'd1;
		end
		
		if(write_data4_strobe_after_cmd)
		begin
			write_data4_strobe_after_cmd <= 0;
			write_data4_strobe <= 1'd1;
		end
	end
	
	if(read_data_strobe)
	begin
		if(read_command_index==8'd5) //IO_SEND_OP_COND
		begin
			write_data[23:0] <= 24'h3C0000;//I/O OCR  3.0-3.4 volts 18-21 bit set
			write_data[24] <= 0;//S18A
			write_data[26:25] <= 0;//stuff bits
			write_data[27] <= 0; //Memory Present
			write_data[30:28] <= 3'd1;//Number of I/O functions
			write_data[31] <= 1'd1; //Set to 1 if Card is ready to operate after initialization
			write_data[37:32] <= 6'b111111; //Bits reserved for future use. These bits shall be set to 1.

			write_data_strobe <= 1'd1;
		end
		
		if(read_command_index==8'd3)//SEND_RELATIVE_ADDR
		begin
			write_data <= 0;
			write_data[13] <= GENERAL_ERROR;
			write_data[14] <= ILLEGAL_COMMAND;
			write_data[15] <= COM_CRC_ERROR;
			reg_rca <= predefined_rca;
			write_data[31:16] <= predefined_rca;
			write_data[37:32] <= 6'd3;
			write_data_strobe <= 1'd1;
		end
		
		if(read_command_index==8'd7)//SELECT/DESELECT_CARD
		begin
			card_selected <= (read_data[31:16]==predefined_rca);
			
			write_data <= 0;
			write_data[31:0] <= reg_card_status;
			write_data[37:32] <= 6'd7;
			write_data_strobe <= 1'd1;
		end
		
		if(read_command_index==8'd53 && read_function_number==3'd1) 
		begin
			data4_count <= cmd53_count;
			send_cmd53 <= 1'd1;
			
			if(read_write_flag)
				read_data4_strobe_after_cmd <= 1'd1;
			else
				write_data4_strobe_after_cmd <= 1'd1;
				
			wait_after_cmd <= 4'd6;
		end
		
		if(read_command_index==8'd52)
		begin
			write_data <= 0;
			send_cmd52 <= 1'd1;
			
			if(read_function_number==3'd1)
			begin
				//Наши самопридуманные регистры
				case(read_register_address[4:0])
				4'd0: begin
						//RX/TX
						cmd52_response_reg_data <= read_counter;
						read_counter <= read_counter+1'd1;
						if(read_counter==8'h7F)
							read_empty <= 1'd1;
					end
					
				4'd1: begin
						//Статус данных
						byte STATUS_DR = 8'h01; //data ready
						byte STATUS_THRE = 8'h02; //transmit empty
						cmd52_response_reg_data <= (read_empty?8'd0:STATUS_DR) | STATUS_THRE;
					end
				default: begin
						INVALID_FUNCTION_NUMBER <= 1'd1;
					end
				endcase
			end
			else
			if(read_register_address>=17'h1000)
			begin
				cmd52_response_reg_data <= cis_array[read_register_address[5:0]];
			end
			else
			case(read_register_address)
			17'h0: begin
					//CCCR/SDIO Revision
					//02 - CCCR/FBR defined in SDIO Version 2.00
					//30 - SDIO Specification Version 2.00
					cmd52_response_reg_data <= 8'h32;
				end
				
			17'h2: begin
					//I/O Enable
					cmd52_response_reg_data <= 8'h2;
				end
			17'h3: begin
					//I/O Ready
					cmd52_response_reg_data <= 8'h2;
				end
			17'h4: begin
					//Int Enable
					cmd52_response_reg_data <= 0;
				end
			17'h6: begin
					//I/O Abort
					cmd52_response_reg_data <= 0;
				end
				
			17'h7: begin
					//I/O Abort
					cmd52_response_reg_data <= 8'h2; //4 bit bus width
				end
				
			17'h8: begin
					//Card Capability
					const byte REG8_4BLS = 8'h80; //bit7 - 4BLS 4-bit Mode Support for Low-Speed Card
					const byte REG8_LSC  = 8'h40; //bit6 - LSC Low-Speed Card
					const byte REG8_E4MI = 8'h20; //bit5 - E4MI Enable Block Gap Interrupt
					const byte REG8_S4MI = 8'h10; //bit4 - S4MI Support Block Gap Interrupt
					const byte REG8_SBS  = 8'h08; //bit3 - SBS Support Bus Control
					const byte REG8_SRW  = 8'h04; //bit2 - SRW Support Read Wait
					const byte REG8_SMB  = 8'h02; //bit1 - SMB Support Multiple Block Transfer (CMD53)
					const byte REG8_SDC  = 8'h01; //bit0 - SDC Support Direct Command (CMD52)
					
					cmd52_response_reg_data <= REG8_4BLS | REG8_SDC;
				end
				
			17'h9: begin
					//CIS address 001000h
					//0 byte
					cmd52_response_reg_data <= 0;
				end
			17'hA: begin
					//CIS address 001000h
					//1 byte
					cmd52_response_reg_data <= 8'h10;
				end
			17'hB: begin
					//CIS address 001000h
					//2 byte
					cmd52_response_reg_data <= 0;
				end
				
			17'h12: begin
					//Power Control
					cmd52_response_reg_data <= 0;
				end
				
			17'h13: begin
					//Bus Speed Select
					const byte REG13_BSS2 = 8'h08;
					const byte REG13_BSS1 = 8'h04;
					const byte REG13_BSS0 = 8'h02;
					const byte REG13_SHS  = 8'h01;
					//BSS[2:0] = 001b SDR25 Max Clock Frequency=50 MHz

					cmd52_response_reg_data <= REG13_BSS0;
				end
				
				//FBR registers
			17'h100: begin
					//UART not support CSA
					cmd52_response_reg_data <= 8'h1;
				end
				
			17'h109: begin
					//CIS address 00100Dh
					//0 byte
					cmd52_response_reg_data <= 8'h0D;
				end
			17'h10A: begin
					//CIS address 00100Dh
					//1 byte
					cmd52_response_reg_data <= 8'h10;
				end
			17'h10B: begin
					//CIS address 00100Dh
					//2 byte
					cmd52_response_reg_data <= 0;
				end
				
			17'h110: begin
					//Block size
					if(read_write_flag)
					begin
						block_size[7:0] <= read_register_data;
						cmd52_response_reg_data <= read_register_data;
					end
					else
					begin
						cmd52_response_reg_data <= block_size[7:0];
					end
				end
				
			17'h111: begin
					//Block size
					if(read_write_flag)
					begin
						block_size[15:8] <= read_register_data;
						cmd52_response_reg_data <= read_register_data;
					end
					else
					begin
						cmd52_response_reg_data <= block_size[15:8];
					end
				end
			default: begin
					INVALID_FUNCTION_NUMBER <= 1'd1;
				end
			endcase
		end
	end
end

endmodule
