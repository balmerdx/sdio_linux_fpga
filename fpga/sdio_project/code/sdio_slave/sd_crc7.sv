/*
 * Author:	Dmitriy 'Balmer' Poskryakov
 * Created:	2020
 * License: MIT License
*/

/*
	Принимает данные по битикам.
	Типично первые 40 бит надо передавать в эту функцию.
*/
module sd_crc7(
	input bit clock,
	input bit clear,
	input bit enable, //только если enable==1 производим обработку
	input bit in_bit, //Бит данных который мы обрабатываем
	output bit[6:0] crc);
	
   bit bit0;
   assign bit0 = in_bit ^ crc[6];
   
   always @(posedge clock)
	begin
		if (enable)
		begin
			crc[6] <= crc[5];
			crc[5] <= crc[4];
			crc[4] <= crc[3];
			crc[3] <= crc[2] ^ bit0;
			crc[2] <= crc[1];
			crc[1] <= crc[0];
			crc[0] <= bit0;
		end
		
      if (clear)
         crc <= 0;
	end
  
endmodule
