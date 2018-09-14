// 24 hour clock

module clock(
	input						clk,						// 50 MHz - 20 ns
	input		[1:0]			keys,						// keys[0] = function key (K4) / keys[1] = up key (K5) - Active low
	
	output	reg	[7:0]	anodes,					// Active low
	output	reg	[7:0]	segments					// Active low
);

	reg	[19:0]	t;									// Time
															// [3:0] Sec (0 - 9)
															// [6:4] Sec x 10 (0 - 5)
															// [10:7] Min (0 - 9)
															// [13:11] Min x 10 (0 - 5)
															// [17:14] Hr (0 - 9)
															// [19:18] Hr x 10 (0 - 2)
															
	reg	[24:0]	counter;							// Enough to count up to 25000000 (half_second and quarter_second clocks)
	reg				half_sec;						// Half second (for the clock)
	reg				quarter_sec;					// Quarter second (to set mins and hrs)
	
	reg	[17:0]	counter_mux;					// Free running counter used for 7-seg mux and keys debouncing
	reg	[3:0]		display;							// Current digit value to display
	reg	[1:0]		deb1, deb2, deb3;				// Debounce registers
	wire	[1:0]		keys_d;							// Debounced keys
	
	reg	[1:0]		fsm;								// Finite state machine status

	wire				inc_time;						// Increment t (partly or in a whole, depending on the status - fsm) on neg edge
	
	`define	STATUS_RUN			2'b00
	`define	STATUS_SET_MIN		2'b01
	`define	STATUS_SET_HR		2'b10
	`define	STATUS_PREVIEW		2'b11

	initial
	begin
		anodes = 8'b11111111;
		segments = 8'b11111111;
//		t = 20'b10_0011__101_1000__100_0110;		// Initial value 2 3 - 5 8 - 4 6
	end

	// Keys debounce (approx 15 ms)
	
	always @ (posedge counter_mux[17])	// Every 131072 x 40 ns = 5.24... ms
	begin
		deb1 <= keys;
		deb2 <= deb1;
		deb3 <= deb2;
	end
	
	assign keys_d = (deb1 | deb2 | deb3);

	// Function key FSM

	always @ (negedge keys_d[0])	// Function key pressed
	begin
		fsm = fsm + 2'd1;		
		if (fsm > `STATUS_PREVIEW)
		begin
			fsm = `STATUS_RUN;
		end
	end
	
	// Mux and debounce counter - Free running
	
	always @ (posedge clk)
	begin
		counter_mux <= counter_mux + 1'b1;
	end

	// Every 655360 ns (0.65... ms) = 16384 x 40 ns,
	// check value of the "digit counter" (3 bits higher = 8),
	// set the current display value, set anodes and segments accordingly
	
	// Note the blocking statements (=) to ensure the assignements are done sequentially
	
	always @ (posedge counter_mux[14])
	begin
		case(counter_mux[17:15])
			3'd0 : begin	display = (fsm == `STATUS_RUN ? t[3:0] : 4'd15);								anodes = 8'b11111110;		end
			3'd1 : begin	display = (fsm == `STATUS_RUN ? {1'b0, t[6:4]} : 4'd15);						anodes = 8'b11111101;		end
			3'd2 : begin	display = (fsm == `STATUS_RUN ? (half_sec ? 4'd10 : 4'd15) : 4'd15);		anodes = 8'b11111011;		end	// 10 stands for "-" / 15 stands for blank
			3'd3 : begin	display = (fsm == `STATUS_SET_HR ? 4'd15 : t[10:7]);							anodes = 8'b11110111;		end
			3'd4 : begin	display = (fsm == `STATUS_SET_HR ? 4'd15 : {1'b0, t[13:11]});				anodes = 8'b11101111;		end
			3'd5 : begin	display = (fsm == `STATUS_RUN ? (half_sec ? 4'd10 : 4'd15) : 4'd15);		anodes = 8'b11011111;		end	// 10 stands for "-" / 15 stands for blank
			3'd6 : begin	display = (fsm == `STATUS_SET_MIN ? 4'd15 : t[17:14]);						anodes = 8'b10111111;		end
			3'd7 : begin	display = (fsm == `STATUS_SET_MIN ? 4'd15 : {2'b00, t[19:18]});			anodes = 8'b01111111;		end
		endcase

		case(display)
			4'd0 : segments = 8'b11000000;	// --fedcba
			4'd1 : segments = 8'b11111001;	// -----cb-
			4'd2 : segments = 8'b10100100;	// -g-ed-ba
			4'd3 : segments = 8'b10110000;	// -g--dcba
			4'd4 : segments = 8'b10011001;	// -gf--cb-
			4'd5 : segments = 8'b10010010;	// -gf-dc-a
			4'd6 : segments = 8'b10000010;	// -gfedc-a
			4'd7 : segments = 8'b11111000;	// -----cba
			4'd8 : segments = 8'b10000000;	// -gfedcba
			4'd9 : segments = 8'b10010000;	// -gf-dcba
			4'd10 : segments = 8'b10111111;	// -g------
			4'd15 : segments = 8'b11111111;	// Blank
		endcase
	end

	// Half-second and Quarter-second counter
	
	always @ (posedge clk)
	if (fsm == `STATUS_PREVIEW)	// Reset counter, half_sec and quarter_sec clocks
	begin
		counter <= 25'd0;
		half_sec <= 1'b0;
		quarter_sec <= 1'b0;
	end
	else
	begin
		if (counter == 12500000)
			quarter_sec <= ~ quarter_sec;
		if (counter <= 25000000)
		begin
			counter <= counter + 25'd1;
		end
		else
		begin
			counter <= 25'd0;
			half_sec <= ~half_sec;
			quarter_sec <= ~ quarter_sec;
		end
	end
	
	// Clock time and Display updates
	
	// For every 1/2 sec edge and up key keys_d[1] action when setting time 

	assign inc_time = ((half_sec & (fsm == `STATUS_RUN))	// Half second when clock is running
							| ((fsm == `STATUS_SET_MIN | fsm == `STATUS_SET_HR) & (keys_d[1] | (!keys_d[1] & quarter_sec) )));
	
	// Note the blocking statements (=) to ensure the assignements are done sequentially

	always @ (negedge inc_time)
	if (fsm == `STATUS_PREVIEW)	// Reset seconds
	begin
		t[6:0] <= 7'b0;
	end
	else
	begin
		case (fsm)
			`STATUS_RUN :	// Inc clock
				begin
					t[3:0] = t[3:0] + 4'd1;
					if (t[3:0] >= 4'd10)
					begin
						t[3:0] = 4'd0;
						t[6:4] = t[6:4] + 3'd1;
						if (t[6:4] >= 3'd6)
						begin
							t[6:4] = 3'd0;
							t[10:7] = t[10:7] + 4'd1;
							if (t[10:7] >= 4'd10)
							begin
								t[10:7] = 4'd0;
								t[13:11] = t[13:11] + 3'd1;
								if (t[13:11] >= 3'd6)
								begin
									t[13:11] = 3'd0;
									t[17:14] = t[17:14] + 4'd1;
									if (t[17:14] >= 4'd10)
									begin
										t[17:14] = 4'd0;
										t[19:18] = t[19:18] + 2'd1;
									end
									if (t[19:14] == 6'h24)
									begin
										t[19:14] = 6'd0;
									end
								end
							end
						end
					end
				end
			
			`STATUS_SET_HR :	// Inc hr only and reset when 24
				begin
					t[17:14] = t[17:14] + 4'd1;
					if (t[17:14] >= 4'd10)
					begin
						t[17:14] = 4'd0;
						t[19:18] = t[19:18] + 2'd1;
					end
					if (t[19:14] == 6'h24)
					begin
						t[19:14] = 6'd0;
					end
				end

			`STATUS_SET_MIN :	// Inc min only and reset when 60
				begin
					t[10:7] = t[10:7] + 4'd1;
					if (t[10:7] >= 4'd10)
					begin
						t[10:7] = 4'd0;
						t[13:11] = t[13:11] + 3'd1;
						if (t[13:11] >= 3'd6)
						begin
							t[13:7] = 7'd0;
						end
					end
				end	
				
		endcase
	end

endmodule

