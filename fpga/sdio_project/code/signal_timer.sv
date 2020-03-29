//Через интервал CLOCKS_PER_TICK выдает сигнал 1 на один такт
module signal_timer
	#(parameter CLOCKS_PER_TICK = 100)
	(
	input bit clock,
	output bit signal_out
	);
	
bit [$clog2(CLOCKS_PER_TICK):0] clock_count = 0;
initial signal_out = 0;
	
always_ff @(posedge clock)
begin
	if(clock_count==CLOCKS_PER_TICK-1)
	begin
		clock_count <= 0;
		signal_out <= 1;
	end
	else
	begin
		clock_count <= clock_count+1'd1;
		signal_out <= 0;
	end
end

endmodule
