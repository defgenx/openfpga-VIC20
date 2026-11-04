-- tb_vic.vhd - VIC20_MiSTer's M6561 blanking geometry, as vic20_video sees it
-- (clk_sys, I_ENA_4 = clk_sys/8, I_CENTER "11", I_WIDE '0'). Prints the unblanked pixels per
-- line and lines per frame of the third frame; vic20_video.sv and video.json use them.
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity tb_vic is generic (NTSC : integer := 0); end;
architecture sim of tb_vic is
	signal clk, ena, rst_l : std_logic := '0';
	signal hb, vb : std_logic;
	signal div : unsigned(2 downto 0) := (others => '0');
	signal pal : std_logic;
begin
	pal <= '0' when NTSC = 1 else '1';
	clk <= not clk after 14 ns;
	process (clk) begin if rising_edge(clk) then div <= div + 1; end if; end process;
	ena <= '1' when div = 0 else '0';
	rst_l <= '1' after 1 us;
	vic : entity work.M6561 port map (
		I_CLK => clk, I_ENA_4 => ena, I_RESET_L => rst_l, O_ENA_1MHZ => open, O_P2_H => open,
		O_P2_H_RISE => open, O_P2_H_FALL => open, I_RW_L => '1', I_ADDR => (others => '0'), O_ADDR => open,
		I_DATA => (others => '0'), O_DATA => open, O_DATA_OE_L => open, O_AUDIO => open,
		O_VIDEO_R => open, O_VIDEO_G => open, O_VIDEO_B => open, O_HSYNC => open, O_VSYNC => open,
		O_COMP_SYNC_L => open, O_HBLANK => hb, O_VBLANK => vb, I_CENTER => "11", I_PAL => pal,
		I_WIDE => '0', I_LIGHT_PEN => '0', I_POTX => (others => '0'), I_POTY => (others => '0'));
	process (clk)
		variable px, maxpx, minpx, lines, frames : integer := 0;
		variable hb_d, vb_d : std_logic := '1';
	begin
		if rising_edge(clk) then
			if ena = '1' and hb = '0' and vb = '0' then px := px + 1; end if;
			if hb = '1' and hb_d = '0' then
				if px > 0 then lines := lines + 1; if px > maxpx then maxpx := px; end if;
					if minpx = 0 or px < minpx then minpx := px; end if; end if;
				px := 0;
			end if;
			if vb = '1' and vb_d = '0' then
				frames := frames + 1;
				if frames = 3 then
					report "frame " & integer'image(minpx) & "-" & integer'image(maxpx) & " x " & integer'image(lines);
					std.env.finish;
				end if;
				lines := 0; maxpx := 0; minpx := 0;
			end if;
			hb_d := hb; vb_d := vb;
		end if;
	end process;
end;
