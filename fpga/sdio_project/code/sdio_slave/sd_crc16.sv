/*
 * Author:	Dmitriy 'Balmer' Poskryakov
 * Created:	2020
 * License: MIT License
*/

/*
	Считает CRC16 пригодное для sd карты.
	Принимает данные 1 бит.
*/
module sd_crc16(
	input bit clock,
	input bit clear,
	input bit enable, //только если enable==1 производим обработку
	input bit in, //1 бит данных который мы обрабатываем
	output bit[15:0] crc);
	
   bit xored;
	bit[15:0] bit_to_xor;
	bit[15:0] bit_shifted;
   assign xored = in ^ crc[15];
	assign bit_to_xor = {3'd0, xored, 6'd0, xored, 5'd0};
	assign bit_shifted = {crc[14:0], xored};
   
   always @(posedge clock)
	begin
		if (enable)
			crc <= bit_shifted ^ bit_to_xor;
		
      if (clear)
         crc <= 0;
	end
  
endmodule
