library ieee;
use ieee.std_logic_1164.all;

library unisim;
use unisim.vcomponents.all;

entity pll_top is
	port (
		clk			: in  std_logic;
		clk_sel		: in  std_logic;
		clk_lock		: out std_logic := '0';
		
		clk_src		: out std_logic := '0';
		clk_out		: out std_logic := '0';
		clk_i2s		: out std_logic := '0'
	);
end pll_top;

architecture rtl of pll_top is
	constant PLL_PERIOD		: real := 40.6901;
	
	signal pll_clk_in			: std_logic := '0';
	
	signal pll0_clk_fb		: std_logic := '0';
	signal pll0_locked		: std_logic := '0';
	signal pll0_clk_o_src	: std_logic := '0';
	signal pll0_clk_o_out	: std_logic := '0';
	signal pll0_clk_o_i2s	: std_logic := '0';
	
	signal pll1_clk_fb		: std_logic := '0';
	signal pll1_locked		: std_logic := '0';
	signal pll1_clk_o_i2s	: std_logic := '0';
	
	signal buf_clk_sel		: std_logic_vector( 2 downto 0 ) := ( others => '0' );
	signal buf_clk_i2s_22	: std_logic := '0';
	signal buf_clk_i2s_24	: std_logic := '0';
	signal buf_clk_i2s		: std_logic := '0';
begin
	
	clk_i2s <= buf_clk_i2s;
	clk_lock <= pll0_locked and pll1_locked;
	
	clk_sel_process : process( buf_clk_i2s )
	begin
		if rising_edge( buf_clk_i2s ) then
			buf_clk_sel <= buf_clk_sel( 1 downto 0 ) & clk_sel;
		end if;
	end process clk_sel_process;
	
	INST_IBUFG_IN : IBUFG
		port map (
			I	=> clk,
			O	=> pll_clk_in
		);
	
	INST_BUFG_PLL0_SRC : BUFG
		port map (
			I	=> pll0_clk_o_src,
			O	=> clk_src
		);
	
	INST_BUFG_PLL0_OUT : BUFG
		port map (
			I	=> pll0_clk_o_out,
			O	=> clk_out
		);
	
	INST_BUFG_PLL0_I2S : BUFG
		port map (
			I	=> pll0_clk_o_i2s,
			O	=> buf_clk_i2s_24
		);
	
	INST_BUFG_PLL1_I2S : BUFG
		port map (
			I	=> pll1_clk_o_i2s,
			O	=> buf_clk_i2s_22
		);
	
	INST_BUFGMUX_I2S : BUFGMUX
		generic map (
			CLK_SEL_TYPE => "SYNC"
		)
		port map (
			S	=> buf_clk_sel( 2 ),
			I0	=> buf_clk_i2s_22,
			I1	=> buf_clk_i2s_24,
			O	=> buf_clk_i2s
		);
	
	INST_PLL0 : PLL_BASE
		generic map (
			BANDWIDTH				 => "OPTIMIZED",
			CLKFBOUT_MULT			 => 24,
			CLKFBOUT_PHASE			 => 0.0,
			CLKIN_PERIOD			 => PLL_PERIOD,
			
			CLKOUT0_DIVIDE			 => 4,
			CLKOUT1_DIVIDE			 => 6,
			CLKOUT2_DIVIDE			 => 24,
			
			CLK_FEEDBACK			 => "CLKFBOUT",
			COMPENSATION			 => "SYSTEM_SYNCHRONOUS",
			DIVCLK_DIVIDE			 => 1,
			REF_JITTER				 => 0.100,
			RESET_ON_LOSS_OF_LOCK => FALSE
		)
		port map (
			CLKFBOUT => pll0_clk_fb,
			CLKOUT0	=> pll0_clk_o_src,
			CLKOUT1	=> pll0_clk_o_out,
			CLKOUT2	=> pll0_clk_o_i2s,
			CLKOUT3	=> open,
			CLKOUT4	=> open,
			CLKOUT5	=> open,
			LOCKED	=> pll0_locked,
			CLKFBIN	=> pll0_clk_fb,
			CLKIN		=> pll_clk_in,
			RST		=> '0'
	);

	INST_PLL1 : PLL_BASE
		generic map (
			BANDWIDTH				 => "OPTIMIZED",
			CLKFBOUT_MULT			 => 34,
			CLKFBOUT_PHASE			 => 0.0,
			CLKIN_PERIOD			 => PLL_PERIOD,
			
			CLKOUT0_DIVIDE			 => 37,
			
			CLK_FEEDBACK			 => "CLKFBOUT",
			COMPENSATION			 => "DCM2PLL",
			DIVCLK_DIVIDE			 => 1,
			REF_JITTER				 => 0.100,
			RESET_ON_LOSS_OF_LOCK => FALSE
		)
		port map (
			CLKFBOUT => pll1_clk_fb,
			CLKOUT0	=> pll1_clk_o_i2s,
			CLKOUT1	=> open,
			CLKOUT2	=> open,
			CLKOUT3	=> open,
			CLKOUT4	=> open,
			CLKOUT5	=> open,
			LOCKED	=> pll1_locked,
			CLKFBIN	=> pll1_clk_fb,
			CLKIN		=> pll_clk_in,
			RST		=> '0'
	);

end rtl;
