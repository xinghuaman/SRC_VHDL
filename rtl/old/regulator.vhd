library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity regulator_top is
	generic (
		CLOCK_COUNT		: integer := 512;
		REG_AVE_WIDTH	: integer range 2 to 6 := 4;
		REG_CNT_WIDTH	: integer range 2 to 6 := 4
	);
	port (
		clk				: in  std_logic;
		rst				: in  std_logic;
		
		-- input/output sample has arrived
		-- input from ring buffer
		-- let's us know how full the buffer is
		i_sample_en		: in  std_logic;
		o_sample_en		: in  std_logic;
		i_fifo_level	: in  unsigned( 10 downto 0 );
		
		-- ratio data - indicate that a ratio has been calculated
		-- locked status indicator
		o_ratio			: out unsigned( 23 + REG_AVE_WIDTH downto 0 ) := ( others => '0' );
		o_locked			: out std_logic := '0';
		o_ratio_en		: out std_logic := '0';
		
		-- shared divider i/o
		div_busy			: in  std_logic;
		div_remainder	: in  unsigned( 24 downto 0 );
		
		div_en			: out std_logic := '0';
		div_divisor		: out unsigned( 26 downto 0 ) := ( others => '0' );
		div_dividend	: out unsigned( 26 downto 0 ) := to_unsigned( CLOCK_COUNT * ( 2**REG_CNT_WIDTH ), 27 )
		
	);
end regulator_top;

architecture rtl of regulator_top is
	type STATE_TYPE is ( S0_WAIT, S1_DIVIDE, S2_DIVIDE_WAIT, S3_REGULATOR );
	signal state			: STATE_TYPE := S0_WAIT;

	signal ptr_rst			: std_logic := '0';
	signal locked			: std_logic := '0';
	signal sample_en		: std_logic := '0';
	
	-- I/O - counter
	signal cnt_en			: std_logic := '0';
	signal cnt_ack			: std_logic := '0';
	signal cnt				: unsigned( 18 downto 0 ) := ( others => '0' );
	
	-- I/O - averager
	signal ave_in_en		: std_logic := '0';
	signal ave_in			: unsigned( 23 downto 0 ) := ( others => '0' );
	signal ave_out_en		: std_logic := '0';
	signal ave_out			: unsigned( 23 + REG_AVE_WIDTH downto 0 ) := ( others => '0' );
	
	-- I/O - divider to averager
	signal reg_out			: unsigned( 23 + REG_AVE_WIDTH downto 0 ) := ( others => '0' );
	signal reg_out_en		: std_logic := '0';
	
	component reg_ratio is
		generic (
			REG_AVE_WIDTH	: integer range 2 to 6
		);
		port (
			clk				: in  std_logic;
			rst				: in  std_logic;
			
			i_fifo_level	: in  unsigned( 10 downto 0 );
			i_ratio			: in  unsigned( 23 + REG_AVE_WIDTH downto 0 );
			i_ratio_en		: in  std_logic;
			o_sample_en		: in  std_logic;
			
			o_locked			: out std_logic;
			o_ratio			: out unsigned( 23 + REG_AVE_WIDTH downto 0 );
			o_ratio_en		: out std_logic
		);
	end component reg_ratio;
	
	component reg_average is
		generic (
			REG_AVE_WIDTH	: integer range 2 to 6
		);
		port (
			clk				: in  std_logic;
			ptr_rst			: in  std_logic;
			
			ratio				: in  unsigned( 23 downto 0 );
			ratio_en			: in  std_logic;
			
			ave				: out unsigned( 23 + REG_AVE_WIDTH downto 0 );
			ave_en			: out std_logic
		);
	end component reg_average;
	
	component reg_count is
		generic (
			REG_CNT_WIDTH	: integer range 2 to 6
		);
		port (
			clk				: in  std_logic;
			rst				: in  std_logic;
			
			i_sample_en		: in  std_logic;
			i_reg_ack		: in  std_logic;
			o_reg				: out unsigned( 18 downto 0 );
			o_reg_en			: out std_logic
		);
	end component reg_count;
begin
	o_locked <= locked;
	
	ptr_rst <= not locked;
	
	div_divisor <= RESIZE( cnt, div_divisor'length );
	
	state_process : process( clk )
	begin
		if rising_edge( clk ) then
			div_en <= '0';
			ave_in_en <= '0';
			o_ratio <= reg_out;
			o_ratio_en <= reg_out_en;
			cnt_ack <= '0';
			
			if rst = '1' then
				state <= S0_WAIT;
				o_ratio_en <= '0';
			else
				case state is
					when S0_WAIT =>
						if o_sample_en = '1' then
							if cnt_en = '1' then
								cnt_ack <= '1';
								state <= S1_DIVIDE;
							else
								o_ratio_en <= '1';
							end if;
						end if;
					
					when S1_DIVIDE =>
						div_en <= not div_busy;
						if div_busy = '1' then
							state <= S2_DIVIDE_WAIT;
						end if;
					
					when S2_DIVIDE_WAIT =>
						ave_in_en <= not div_busy;
						if div_busy = '0' then
							ave_in <= div_remainder( 23 downto 0 );
							state <= S3_REGULATOR;
						end if;
					
					when S3_REGULATOR =>
						if reg_out_en = '1' then
							state <= S0_WAIT;
						end if;
					
				end case;
			end if;
		end if;
	end process state_process;

	INST_COUNTER : reg_count
		generic map (
			REG_CNT_WIDTH	=> REG_CNT_WIDTH
		)
		port map (
			clk				=> clk,
			rst				=> rst,
			
			i_sample_en		=> i_sample_en,
			i_reg_ack		=> cnt_ack,
			o_reg				=> cnt,
			o_reg_en			=> cnt_en
		);
	
	INST_AVERAGE : reg_average
		generic map (
			REG_AVE_WIDTH	=> REG_AVE_WIDTH
		)
		port map (
			clk				=> clk,
			ptr_rst			=> ptr_rst,
			
			ratio				=> ave_in,
			ratio_en			=> ave_in_en,
			
			ave				=> ave_out,
			ave_en			=> ave_out_en
		);
	
	INST_RATIO : reg_ratio
		generic map (
			REG_AVE_WIDTH	=> REG_AVE_WIDTH
		)
		port map (
			clk				=> clk,
			rst				=> rst,
			
			i_fifo_level	=> i_fifo_level,
			o_sample_en		=> o_sample_en,
			
			i_ratio			=> ave_out,
			i_ratio_en		=> ave_out_en,
			
			o_locked			=> locked,
			o_ratio			=> reg_out,
			o_ratio_en		=> reg_out_en
		);
end rtl;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.src.all;

entity reg_ratio is
	generic (
		REG_AVE_WIDTH	: integer range 2 to 6 := 4
	);
	port (
		clk				: in  std_logic;
		rst				: in  std_logic;
		
		i_fifo_level	: in  unsigned( 10 downto 0 );
		i_ratio			: in  unsigned( 23 + REG_AVE_WIDTH downto 0 );
		i_ratio_en		: in  std_logic;
		o_sample_en		: in  std_logic;
		
		o_locked			: out std_logic := '0';
		o_ratio			: out unsigned( 23 + REG_AVE_WIDTH downto 0 ) := ( others => '0' );
		o_ratio_en		: out std_logic := '0'
	);
end reg_ratio;

architecture rtl of reg_ratio is
	constant FIFO_SET_PT		: integer := 2**8;
	constant THRESHOLD_LOCK	: integer := 0;
	constant THRESHOLD_VARI	: integer := 2**6;
	
	signal err_term		: unsigned( 10 downto 0 ) := ( others => '0' );
	signal err_ptr			: unsigned( 10 downto 0 ) := ( others => '0' );
	signal err_track		: unsigned( 15 downto 0 ) := ( others => '0' );
	
	signal sum_vari		: unsigned( 23 + REG_AVE_WIDTH downto 0 ) := ( others => '0' );
	signal sum_lock		: unsigned( 23 + REG_AVE_WIDTH downto 0 ) := ( others => '0' );
	
	signal locked			: std_logic := '0';
	signal reg_ratio		: unsigned( 23 + REG_AVE_WIDTH downto 0 ) := ( others => '0' );
	signal ratio_en_buf	: std_logic_vector( 5 downto 0 ) := ( others => '0' );
	
	component ratio_filter is
		generic (
			REG_AVE_WIDTH	: integer range 2 to 6 := 4
		);
		port (
			clk			: in  std_logic;
			rst			: in  std_logic;
			ctrl_lock	: in  std_logic;
			
			o_sample_en	: in  std_logic;
			
			i_ratio		: in  unsigned( 23 + REG_AVE_WIDTH downto 0 );
			i_ratio_en	: in  std_logic;
			
			o_error		: out unsigned( 15 downto 0 );
			o_ratio		: out unsigned( 23 + REG_AVE_WIDTH downto 0 );
			o_ratio_en	: out std_logic
		);
	end component ratio_filter;
begin

	o_ratio  <= reg_ratio;
	o_locked <= locked;
	
	lock_process : process( clk )
	begin
		if rising_edge( clk ) then
			if rst = '1' then
				locked <= '0';
			elsif i_ratio_en = '1' then
				if err_track <= THRESHOLD_LOCK and reg_ratio >= 512 then
					locked <= '1';
				end if;
				
				if locked = '1' and err_ptr > THRESHOLD_VARI then
					locked <= '0';
				end if;
			end if;
		end if;
	end process lock_process;
	
	-------------------------------------------------------------------------
	-- Error magnitude terms
	-------------------------------------------------------------------------
	err_term <= i_fifo_level - FIFO_SET_PT;
	
	err_mag_process : process( clk )
	begin
		if rising_edge( clk ) then
			err_ptr <= unsigned( abs( signed( err_term ) ) );
		end if;
	end process err_mag_process;
	
	-------------------------------------------------------------------------
	-- Ramp Generator
	-------------------------------------------------------------------------
	INST_RAMP : ratio_filter
		generic map (
			REG_AVE_WIDTH	=> REG_AVE_WIDTH
		)
		port map (
			clk			=> clk,
			rst			=> rst,
			ctrl_lock	=> locked,
			
			o_sample_en	=> o_sample_en,
			
			i_ratio		=> i_ratio,
			i_ratio_en	=> i_ratio_en,
			
			o_error		=> err_track,
			o_ratio		=> reg_ratio,
			o_ratio_en	=> o_ratio_en
		);
end rtl;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity reg_average is
	generic (
		REG_AVE_WIDTH	: integer range 0 to 6 := 6
	);
	port (
		clk			: in  std_logic;
		ptr_rst		: in  std_logic;
		
		ratio			: in  unsigned( 23 downto 0 );
		ratio_en		: in  std_logic;
		
		ave			: out unsigned( 23 + REG_AVE_WIDTH downto 0 ) := ( others => '0' );
		ave_en		: out std_logic := '0'
	);
end reg_average;

architecture rtl of reg_average is
	signal ptr_reset	: std_logic_vector( 1 downto 0 ) := ( others => '0' );
	
	type SR_TYPE is array( 2**REG_AVE_WIDTH - 1 downto 0 ) of unsigned( 24 downto 0 );
	signal sr				: SR_TYPE := ( others => ( others => '0' ) );
	alias  sr_out			: unsigned( 23 downto 0 ) is sr( 2**REG_AVE_WIDTH - 1 )( 23 downto 0 );
	
	signal preload			: std_logic := '0';
	alias  preload_out	: std_logic is sr( 2**REG_AVE_WIDTH - 1 )( 24 );
	signal preload_in		: std_logic := '0';
	
	signal buf_ratio		: unsigned( 23 downto 0 ) := ( others => '0' );
	signal buf_ratio_en	: std_logic := '0';
	
	signal moving_sum		: unsigned( 23 + REG_AVE_WIDTH downto 0 ) := ( others => '0' );
begin

	ave <= moving_sum;

	ptr_reset_process : process( clk )
	begin
		if rising_edge( clk ) then
			ptr_reset <= ptr_reset( 0 ) & ( ptr_rst and ratio_en );
		end if;
	end process ptr_reset_process;
	
	preload_process : process( clk )
	begin
		if rising_edge( clk ) then
			if preload = '0' and ptr_reset( 1 ) = '1' then
				preload_in <= '1';
			else
				preload_in <= '0';
			end if;
		end if;
	
		if rising_edge( clk ) then
			if preload_out = '1' then
				preload <= '0';
			elsif ptr_reset( 1 ) = '1' then
				preload <= '1';
			end if;
		end if;
	end process preload_process;
	
	data_process : process( clk )
	begin
		if rising_edge( clk ) then
			buf_ratio_en <= ratio_en;
			ave_en <= buf_ratio_en;
			if ( preload or buf_ratio_en ) = '1' then
				buf_ratio <= ratio;
			end if;
		end if;
	end process data_process;
	
	moving_sum_process : process( clk )
	begin
		if rising_edge( clk ) then
			if buf_ratio_en = '1' then
				moving_sum <= moving_sum + buf_ratio - sr_out;
			elsif preload = '1' then
				moving_sum( 23 + REG_AVE_WIDTH downto REG_AVE_WIDTH ) <= buf_ratio;
				moving_sum( REG_AVE_WIDTH-1 downto 0 ) <= ( others => '0' );
			end if;
		end if;
	end process moving_sum_process;
	
	sr_process : process( clk )
	begin
		if rising_edge( clk ) then
			if ( preload or buf_ratio_en ) = '1' then
				sr <= sr( 2**REG_AVE_WIDTH - 2 downto 0 ) & ( preload_in & buf_ratio );
			end if;
		end if;
	end process sr_process;

end rtl;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.src.all;

entity reg_count is
	generic (
		REG_CNT_WIDTH	: integer range 2 to 6 := 4
	);
	port (
		clk			: in  std_logic;
		rst			: in  std_logic;
		
		--------------------------------------------------
		-- DATA Interfaces
		--------------------------------------------------
		i_sample_en	: in  std_logic;
		
		i_reg_ack	: in  std_logic;
		o_reg			: out unsigned( 18 downto 0 ) := ( others => '0' );
		o_reg_en		: out std_logic := '0'
	);
end reg_count;

architecture rtl of reg_count is
	signal clock_count	: unsigned( 18 downto 0 ) := ( 0 => '1', others => '0' );
	signal frame_buf		: unsigned( 18 downto 0 ) := ( others => '0' );
	signal frame_count	: unsigned( REG_CNT_WIDTH-1 downto 0 ) := ( others => '0' );
	signal frame_en		: std_logic := '0';
	signal state			: std_logic := '0';
begin

	o_reg <= frame_buf;
	o_reg_en <= frame_en;

	count_process : process( clk )
	begin
		if rising_edge( clk ) then
			if i_reg_ack = '1' then
				frame_en  <= '0';
			end if;
			
			if state = '1' then
				clock_count <= clock_count + 1;
				
				if i_sample_en = '1' then
					frame_count <= frame_count + 1;
					
					if frame_count = 2**REG_CNT_WIDTH-1 then
						clock_count <= ( 0 => '1', others => '0' );
						frame_buf	<= clock_count;
						frame_en		<= '1';
					end if;
				end if;
			end if;
		end if;
	end process count_process;
	
	state_process : process( clk )
	begin
		if rising_edge( clk ) then
			if rst = '1' then
				state <= '0';
			elsif i_sample_en = '1' then
				state <= '1';
			end if;
		end if;
	end process state_process;

end rtl;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ratio_filter is
	generic (
		REG_AVE_WIDTH	: integer range 2 to 6 := 4
	);
	port (
		clk			: in  std_logic;
		rst			: in  std_logic;
		ctrl_lock	: in  std_logic;
		
		o_sample_en	: in  std_logic;
		
		i_ratio		: in  unsigned( 23 + REG_AVE_WIDTH downto 0 );
		i_ratio_en	: in  std_logic;
		
		o_error		: out unsigned( 15 downto 0 ) := ( others => '0' );
		o_ratio		: out unsigned( 23 + REG_AVE_WIDTH downto 0 ) := ( others => '0' );
		o_ratio_en	: out std_logic := '0'
	);
end ratio_filter;

architecture rtl of ratio_filter is
	
	signal reg_ratio		: unsigned( 23 + REG_AVE_WIDTH downto 0 ) := ( others => '0' );
	signal reg_latch		: unsigned( 23 + REG_AVE_WIDTH downto 0 ) := ( others => '0' );
	alias  reg_latch_s	: unsigned( 15 downto 0 ) is reg_latch( 23 + REG_AVE_WIDTH downto 8 + REG_AVE_WIDTH );
	
	signal reg_latch_en	: std_logic := '0';
	signal err_abs			: unsigned( 23 + REG_AVE_WIDTH downto 0 ) := ( others => '0' );
	signal lpf_in			: unsigned( 23 + REG_AVE_WIDTH downto 0 ) := ( others => '0' );
	signal lpf_in_en		: std_logic := '0';
	signal lpf_out			: unsigned( 23 + REG_AVE_WIDTH downto 0 ) := ( others => '0' );
	alias  lpf_out_s		: unsigned( 15 downto 0 ) is lpf_out( 23 + REG_AVE_WIDTH downto 8 + REG_AVE_WIDTH );
	signal lpf_out_en		: std_logic := '0';
	
	component lpf is
		generic (
			LPF_WIDTH	: natural range 16 to 32 := 24 + REG_AVE_WIDTH
		);
		port (
			clk			: in  std_logic;
			rst			: in  std_logic;
			ctrl_lock	: in  std_logic;
			
			lpf_in		: in  unsigned( LPF_WIDTH-1 downto 0 );
			lpf_in_en	: in  std_logic;
			
			lpf_out		: out unsigned( LPF_WIDTH-1 downto 0 );
			lpf_out_en	: out std_logic
		);
	end component lpf;
	
begin

	o_ratio <= lpf_out;
	o_ratio_en <= lpf_out_en;
	
	reg_latch_en <= '1' when err_abs > x"1F" else '0';
	
	input_process : process( clk )
	begin
		if rising_edge( clk ) then
			if rst = '1' then
				reg_ratio <= ( others => '0' );
			elsif i_ratio_en = '1' then
				reg_ratio <= i_ratio;
			end if;
			
			if rst = '1' then
				o_error <= ( others => '0' );
				err_abs <= ( others => '0' );
			else
				o_error <= unsigned( abs( signed( reg_latch_s - lpf_out_s ) ) );
				err_abs <= unsigned( abs( signed( reg_ratio   - reg_latch ) ) );
			end if;
		end if;
	end process input_process;
	
	latch_process : process( clk )
	begin
		if rising_edge( clk ) then
			if rst = '1' then
				reg_latch <= ( others => '0' );
			elsif reg_latch_en = '1' then
				reg_latch <= reg_ratio;
			end if;
		end if;
	end process latch_process;
	
	lpf_input_process : process( clk )
	begin
		if rising_edge( clk ) then
			lpf_in_en <= o_sample_en;
			if rst = '1' then
				lpf_in <= ( others => '0' );
				lpf_in_en <= '0';
			elsif o_sample_en = '1' then
				lpf_in <= reg_latch;
			end if;
		end if;
	end process lpf_input_process;
	
	INST_LPF : lpf
		port map (
			clk			=> clk,
			rst			=> rst,
			ctrl_lock	=> ctrl_lock,
			
			lpf_in		=> lpf_in,
			lpf_in_en	=> lpf_in_en,
			
			lpf_out		=> lpf_out,
			lpf_out_en	=> lpf_out_en
		);
	
end rtl;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity lpf is
	generic (
		LPF_WIDTH	: natural range 16 to 42 := 17
	);
	port (
		clk			: in  std_logic;
		rst			: in  std_logic;
		ctrl_lock	: in  std_logic;
		
		lpf_in		: in  unsigned( LPF_WIDTH-1 downto 0 );
		lpf_in_en	: in  std_logic;
		
		lpf_out		: out unsigned( LPF_WIDTH-1 downto 0 ) := ( others => '0' );
		lpf_out_en	: out std_logic := '0'
	);
end lpf;

architecture rtl of lpf is
	signal reg_add		: signed( LPF_WIDTH+11 downto 0 ) := ( others => '0' );
	signal reg_shift	: signed( LPF_WIDTH+11 downto 0 ) := ( others => '0' );
	signal reg_out		: signed( LPF_WIDTH+11 downto 0 ) := ( others => '0' );
begin
	
	lpf_out <= unsigned( reg_out( LPF_WIDTH+10 downto 11 ) );
	reg_add <= signed( '0' & lpf_in & b"000_0000_0000" ) - reg_out;
	
	reg_shift <= shift_right( reg_add,  9 ) when ctrl_lock = '0' else
					 shift_right( reg_add, 11 );
	
	integrator_process : process( clk )
	begin
		if rising_edge( clk ) then
			lpf_out_en <= lpf_in_en;
			if rst = '1' then
				lpf_out_en <= '0';
				reg_out <= ( others => '0' );
			elsif lpf_in_en = '1' then
				reg_out <= reg_out + reg_shift;
			end if;
		end if;
	end process integrator_process;
	
end rtl;
