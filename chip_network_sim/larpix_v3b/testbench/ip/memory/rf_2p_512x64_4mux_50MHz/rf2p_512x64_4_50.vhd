--------------------------------------------------------------------------
--      CONFIDENTIAL AND PROPRIETARY SOFTWARE/DATA OF ARTISAN COMPONENTS, INC.
--      
--      Copyright (c) 2019 Artisan Components, Inc.  All Rights Reserved.
--      
--      Use of this Software/Data is subject to the terms and conditions of
--      the applicable license agreement between Artisan Components, Inc. and
--      Taiwan Semiconductor Manufacturing Company Ltd..  In addition, this Software/Data
--      is protected by copyright law and international treaties.
--      
--      The copyright notice(s) in this Software/Data does not indicate actual
--      or intended publication of this Software/Data.
--      name:			RF-2P-HS Register File Generator
--           			TSMC CL018G Process
--      version:		2003Q2V2
--      comment:		
--      configuration:	 -instname "rf2p_512x64_4_50" -words 512 -bits 64 -frequency 50 -ring_width 10 -mux 4 -drive 3 -write_mask off -wp_size 8 -top_layer met6 -power_type rings -horiz met3 -vert met2 -cust_comment "" -left_bus_delim "[" -right_bus_delim "]" -pwr_gnd_rename "VDD:VDD,GND:VSS" -prefix "" -pin_space 0.0 -name_case upper -check_instname on -diodes on -inside_ring_type GND
--
--      VHDL model for Synchronous Dual-Port Register File
--
--      Instance:       rf2p_512x64_4_50
--      Address Length: 512
--      Word Width:     64
--      Pipeline:       No
--
--      Creation Date:  2019-02-18 16:41:45Z
--      Version:        2003Q2V2
--
--      Verified With:  Model Technology VCOM V-System VHDL
--
--      Modeling Assumptions: This model supports full gate-level simulaton
--          including proper x-handling and timing check behavior.  It is
--          Level 1 VITAL95 compliant.  Unit delay timing is included in the
--          model. Back-annotation of SDF (v2.1) is supported.  SDF can be
--          created utilyzing the delay calculation views provided with this
--          generator and supported delay calculators.  For netlisting
--          simplicity, buses are not exploded.  All buses are modeled
--          [MSB:LSB].  To operate properly, this model must be used with the
--          Artisan's Vhdl packages.
--
--      Modeling Limitations: None.
--
--      Known Bugs: None.
--
--      Known Work Arounds: N/A
--------------------------------------------------------------------------
use std.all;
LIBRARY IEEE;
	use IEEE.std_logic_1164.all;
	use IEEE.VITAL_timing.all;
	use IEEE.VITAL_primitives.all;
	use WORK.vlibs.all; 

Package rf2p_512x64_4_50_pkgs is
 component rf2p_512x64_4_50
   generic(
        TIME_UNIT              : TIME  := 1.0 ns;
        TimingChecksOn	  : boolean := TRUE;
	tipd_AA: VitalDelayArrayType01(8 downto 0):=(others=>(0.000 ns, 0.000 ns));
	tipd_CLKA: VitalDelayType01:=(0.000 ns, 0.000 ns);
	tipd_CENA: VitalDelayType01:=(0.000 ns, 0.000 ns);
	tipd_AB: VitalDelayArrayType01(8 downto 0):=(others=>(0.000 ns, 0.000 ns));
	tipd_DB: VitalDelayArrayType01(63 downto 0):=(others=>(0.000 ns, 0.000 ns));
	tipd_CLKB: VitalDelayType01:=(0.000 ns, 0.000 ns);
	tipd_CENB: VitalDelayType01:=(0.000 ns, 0.000 ns);
	tsetup_AA_CLKA_negedge_posedge: VitalDelayArrayType(8 downto 0):=(others=>(1.000 ns));
	tsetup_AA_CLKA_posedge_posedge: VitalDelayArrayType(8 downto 0):=(others=>(1.000 ns));
	tsetup_CENA_CLKA_negedge_posedge: VitalDelayType:=1.000 ns;
	tsetup_CENA_CLKA_posedge_posedge: VitalDelayType:=1.000 ns;
	thold_AA_CLKA_negedge_posedge: VitalDelayArrayType(8 downto 0):=(others=>(0.500 ns));
	thold_AA_CLKA_posedge_posedge: VitalDelayArrayType(8 downto 0):=(others=>(0.500 ns));
	thold_CENA_CLKA_negedge_posedge: VitalDelayType:=0.500 ns;
	thold_CENA_CLKA_posedge_posedge: VitalDelayType:=0.500 ns;
	tsetup_AB_CLKB_negedge_posedge: VitalDelayArrayType(8 downto 0):=(others=>(1.000 ns));
	tsetup_AB_CLKB_posedge_posedge: VitalDelayArrayType(8 downto 0):=(others=>(1.000 ns));
	tsetup_DB_CLKB_negedge_posedge: VitalDelayArrayType(63 downto 0):=(others=>(1.000 ns));
	tsetup_DB_CLKB_posedge_posedge: VitalDelayArrayType(63 downto 0):=(others=>(1.000 ns));
	tsetup_CENB_CLKB_negedge_posedge: VitalDelayType:=1.000 ns;
	tsetup_CENB_CLKB_posedge_posedge: VitalDelayType:=1.000 ns;
	thold_AB_CLKB_negedge_posedge: VitalDelayArrayType(8 downto 0):=(others=>(0.500 ns));
	thold_AB_CLKB_posedge_posedge: VitalDelayArrayType(8 downto 0):=(others=>(0.500 ns));
	thold_DB_CLKB_negedge_posedge: VitalDelayArrayType(63 downto 0):=(others=>(0.500 ns));
	thold_DB_CLKB_posedge_posedge: VitalDelayArrayType(63 downto 0):=(others=>(0.500 ns));
	thold_CENB_CLKB_negedge_posedge: VitalDelayType:=0.500 ns;
	thold_CENB_CLKB_posedge_posedge: VitalDelayType:=0.500 ns;
        tsetup_CLKB_CLKA_posedge_posedge:  VitalDelayType := 0.50 ns;
        tsetup_CLKA_CLKB_posedge_posedge:  VitalDelayType := 0.50 ns;
	tpd_CLKA_QA: VitalDelayArrayType01(63 downto 0):=(others=>(1.0 ns,1.0 ns));
        tperiod_CLKA           : VitalDelayType  := 2.0 ns; -- min cycle time
        tperiod_CLKB           : VitalDelayType  := 2.0 ns; -- min cycle time
        tpw_CLKA_negedge       : VitalDelayType  := 1.0 ns;
        tpw_CLKA_posedge       : VitalDelayType  := 1.0 ns;
        tpw_CLKB_negedge       : VitalDelayType  := 1.0 ns;
        tpw_CLKB_posedge       : VitalDelayType  := 1.0 ns
   ); 
   port (
	AA: in std_logic_vector(8 downto 0);
	CLKA: in std_logic;
	CENA: in std_logic;
	AB: in std_logic_vector(8 downto 0);
	DB: in std_logic_vector(63 downto 0);
	CLKB: in std_logic;
	CENB: in std_logic;
	QA: out std_logic_vector(63 downto 0)
    );
end component; 
 component read_port_rf2p_512x64_4_50 
   generic(
        TIME_UNIT			: TIME ;
        TimingChecksOn			: boolean:=TRUE;
        PortName			: string;
        tipd_CLK			: VitalDelayType01;
        tipd_A				: VitalDelayArrayType01;
        tipd_CEN			: VitalDelayType01;
        tperiod_CLK			: VitalDelayType;
        tpw_CLK_negedge			: VitalDelayType;
        tpw_CLK_posedge			: VitalDelayType;
        tsetup_CEN_CLK_negedge_posedge	: VitalDelayType;
        tsetup_CEN_CLK_posedge_posedge	: VitalDelayType;
        thold_CEN_CLK_negedge_posedge	: VitalDelayType;
        thold_CEN_CLK_posedge_posedge	: VitalDelayType;
        tsetup_A_CLK_negedge_posedge	: VitalDelayArrayType;
        tsetup_A_CLK_posedge_posedge	: VitalDelayArrayType;
        thold_A_CLK_negedge_posedge	: VitalDelayArrayType;
        thold_A_CLK_posedge_posedge	: VitalDelayArrayType;
	tsetup_CLK_CLKWr_posedge_posedge: VitalDelayType;
	thold_CLK_CLKWr_posedge_posedge	: VitalDelayType;

        tpd_CLK_Q    			: VitalDelayArrayType01
   ); 
   port (
	A     : in std_logic_vector(8 downto 0);
	Am    : out std_logic_vector(8 downto 0);
        CEN   : in std_logic;
        CLK   : in std_logic;
        CLKWr : in std_logic;
        Q     : out std_logic_vector(63 downto 0);
	MEM   : in MEM_TYPE(511 downto 0, 63 downto 0)
    );
 end component; 
 component write_port_rf2p_512x64_4_50 
   generic(
        TIME_UNIT             		: TIME;
        TimingChecksOn	 		: boolean;
        PortName			: string;
        tipd_CLK              		: VitalDelayType01;
        tipd_D                		: VitalDelayArrayType01;
        tipd_A                		: VitalDelayArrayType01;
        tipd_CEN              		: VitalDelayType01;
        tperiod_CLK           		: VitalDelayType;
        tpw_CLK_negedge       		: VitalDelayType;
        tpw_CLK_posedge       		: VitalDelayType;
        tsetup_CEN_CLK_negedge_posedge   : VitalDelayType;
        tsetup_CEN_CLK_posedge_posedge   : VitalDelayType;
        thold_CEN_CLK_negedge_posedge    : VitalDelayType;
        thold_CEN_CLK_posedge_posedge    : VitalDelayType;
        tsetup_D_CLK_negedge_posedge     : VitalDelayArrayType;
        tsetup_D_CLK_posedge_posedge     : VitalDelayArrayType;
        thold_D_CLK_negedge_posedge      : VitalDelayArrayType;
        thold_D_CLK_posedge_posedge      : VitalDelayArrayType;
        tsetup_A_CLK_negedge_posedge     : VitalDelayArrayType;
        tsetup_A_CLK_posedge_posedge     : VitalDelayArrayType;
        thold_A_CLK_negedge_posedge      : VitalDelayArrayType;
        thold_A_CLK_posedge_posedge      : VitalDelayArrayType
   ); 
   port (
        A     : in std_logic_vector(8 downto 0);
        Am    : in std_logic_vector(8 downto 0);
        CEN   : in std_logic;
        CLK   : in std_logic;
        D     : in std_logic_vector(63 downto 0);
	MEM   : inout MEM_TYPE(511 downto 0, 63 downto 0);
        CLKWr : out std_logic
    );
 end component; 
End rf2p_512x64_4_50_pkgs;
--------------------------------------------------------------------------
--
--	Instance:	read_port_rf2p_512x64_4_50
--
--      CONFIDENTIAL AND PROPRIETARY SOFTWARE/DATA OF ARTISAN COMPONENTS, INC.
--      
--      Copyright (c) 2019 Artisan Components, Inc.  All Rights Reserved.
--      
--      Use of this Software/Data is subject to the terms and conditions of
--      the applicable license agreement between Artisan Components, Inc. and
--      Taiwan Semiconductor Manufacturing Company Ltd..  In addition, this Software/Data
--      is protected by copyright law and international treaties.
--      
--      The copyright notice(s) in this Software/Data does not indicate actual
--      or intended publication of this Software/Data.
--
--------------------------------------------------------------------------
use std.all;
lIBRARY IEEE;
	use IEEE.std_logic_1164.all;
	use IEEE.VITAL_timing.all;
	use IEEE.VITAL_primitives.all;
	use WORK.vlibs.all; 
	use WORK.lib_cells_pkgs.all; 
	use work.rf2p_512x64_4_50_pkgs.all;

entity read_port_rf2p_512x64_4_50 is 
   generic(
        TIME_UNIT			: TIME ;
        TimingChecksOn			: boolean:=TRUE;
        PortName			: string;
        tipd_CLK			: VitalDelayType01;
        tipd_A				: VitalDelayArrayType01;
        tipd_CEN			: VitalDelayType01;
        tperiod_CLK			: VitalDelayType;
        tpw_CLK_negedge			: VitalDelayType;
        tpw_CLK_posedge			: VitalDelayType;
        tsetup_CEN_CLK_negedge_posedge	: VitalDelayType;
        tsetup_CEN_CLK_posedge_posedge	: VitalDelayType;
        thold_CEN_CLK_negedge_posedge	: VitalDelayType;
        thold_CEN_CLK_posedge_posedge	: VitalDelayType;
        tsetup_A_CLK_negedge_posedge	: VitalDelayArrayType;
        tsetup_A_CLK_posedge_posedge	: VitalDelayArrayType;
        thold_A_CLK_negedge_posedge	: VitalDelayArrayType;
        thold_A_CLK_posedge_posedge	: VitalDelayArrayType;
	tsetup_CLK_CLKWr_posedge_posedge: VitalDelayType;
	thold_CLK_CLKWr_posedge_posedge	: VitalDelayType;

        tpd_CLK_Q    			: VitalDelayArrayType01
   ); 
   port (
	A     : in std_logic_vector(8 downto 0);
	Am    : out std_logic_vector(8 downto 0);
        CEN   : in std_logic;
        CLK   : in std_logic;
        CLKWr : in std_logic;
        Q     : out std_logic_vector(63 downto 0);
	MEM   : in MEM_TYPE(511 downto 0, 63 downto 0)
    );
    attribute VITAL_LEVEL1 of read_port_rf2p_512x64_4_50 : entity is TRUE;
end read_port_rf2p_512x64_4_50;

architecture BEHAVIORAL of read_port_rf2p_512x64_4_50 is
  constant ClkPort: 	string := cat("CLK", PortName);
  constant GtpPort: 	string := cat("GTP", PortName);
  constant InstPort: 	string := cat("rf2p_512x64_4_50_Port", PortName);
  signal CLK_INT	: std_logic;
  signal GTP_INT	: std_logic;
  signal CLKVio	: std_logic;
  signal ANi     	: std_logic_vector(8 downto 0);
  signal ANVio     	: std_logic_vector(8 downto 0);
  signal CENVio		: std_logic;
  signal CENi		: std_logic;
  signal OEi		: std_logic;
  signal Qi		: std_logic_vector(63 downto 0);

	----------------------------------------------------------------------
Begin

 TPW_CLK: TPwCell   generic map(tipd_clk=>tipd_CLK, tperiod_clk => tperiod_CLK,
                                tpw_clk_posedge => tpw_CLK_posedge, tpw_clk_negedge => tpw_CLK_negedge,
				TestSignalName=>ClkPort, HeaderMsg=>InstPort,
				TimingChecksOn=>TimingChecksOn)
                    port map(out0=>CLK_INT, clk=>CLK);
 TCLKCLKWr: TchCellEdges  generic map(tipd_in0=>tipd_CLK, 
				tsetup_in0_clk_posedge_posedge => tsetup_CLK_CLKWr_posedge_posedge,
                                thold_in0_clk_posedge_posedge => thold_CLK_CLKWr_posedge_posedge, 
                                TestSignalName=>ClkPort, RefSignalName=>"CLKWr", HeaderMsg=>InstPort,
				TimingChecksOn=>TimingChecksOn)
                    port map(clk=>GTP_INT, in0=>CLKWr, out0=>CLKVio);
TA_A_UTI: for i in 0 to 8 generate
TCH_A: TchCellEdges      generic map(tipd_in0=>tipd_A(i), 
				tsetup_in0_clk_negedge_posedge => tsetup_A_CLK_negedge_posedge(i),
                                thold_in0_clk_negedge_posedge => thold_A_CLK_negedge_posedge(i), 
				tsetup_in0_clk_posedge_posedge => tsetup_A_CLK_posedge_posedge(i),
                                thold_in0_clk_posedge_posedge => thold_A_CLK_posedge_posedge(i), 
                                TestSignalName=>ClkPort, RefSignalName=>icat("A","",i), 
				HeaderMsg=>InstPort, TimingChecksOn=>TimingChecksOn)
                    port map(in0=>A(i), clk=>GTP_INT, Violation=>ANVio(i),out0=>ANi(i));

end generate;                      


TCH_CEN: TchCellEdges   generic map(tipd_in0=>tipd_CEN, 
				tsetup_in0_clk_negedge_posedge => tsetup_CEN_CLK_negedge_posedge,
                                thold_in0_clk_negedge_posedge => thold_CEN_CLK_negedge_posedge, 
				tsetup_in0_clk_posedge_posedge => tsetup_CEN_CLK_posedge_posedge,
                                thold_in0_clk_posedge_posedge => thold_CEN_CLK_posedge_posedge, 
                                TestSignalName=>ClkPort, RefSignalName=>cat("CEN",PortName), 
				HeaderMsg=>InstPort, TimingChecksOn=>TimingChecksOn)
                    port map(in0=>CEN, clk=>CLK_INT, Violation=>CENVio,out0=>CENi);

Gtps: process(CLK_INT, CENi)
Begin
  if(CLK_INT'event and CLK_INT='0') then
    GTP_INT <= '0';
  elsif((CENVio='X' and CENi='X') or (CLK_INT='X' and CENi = '0')) then
    GTP_INT <= 'X';
  elsif(CLK_INT'event and CLK_INT='1') then
    GTP_INT <= not(CENi);
  end if;


End process Gtps;

ReadMem: process(GTP_INT, ANVio, CLKVio)
    variable AddVio : boolean;
    variable AddI   : std_logic_vector(ANi'range);
    variable NQi    : std_logic_vector(Qi'range);
    variable NNQi    : std_logic_vector(Qi'range);
	----------------------------------------------------------------------
    Begin
        if(Is_X(ANi)) then AddI:=(others => 'X'); 
        else AddI:=ANi; end if;
        AddVio:= Is_X(ANVio);

        if (GTP_INT'event or AddVio or CLKVio='X') then
          case GTP_INT is
  	    when '1' => 		-- valid rising edge
		READ_MEM(AddI, NQi, MEM);
	    when 'U' | 'X' =>  
		NQi:=(others => 'X') ;
	    when others => 
		null ;
	  end case;
 	            if(CLKVio='X') then
            READ_MEM(AddI, NNQi, MEM);
		NQi:=(others => 'X') ;
          end if;
        end if;
        Qi <= NQi;
        Am <= AddI;
    end process ReadMem ;

QS: for i in 0 to 63 generate
  Q_AMPS: buf	generic map(tpd_in0_out0=>tpd_CLK_Q(i))
		port map(in0=>Qi(i), out0=>Q(i));
end generate;
end behavioral;

--------------------------------------------------------------------------
--	Instance:	write_port_rf2p_512x64_4_50
--      CONFIDENTIAL AND PROPRIETARY SOFTWARE/DATA OF ARTISAN COMPONENTS, INC.
--      
--      Copyright (c) 2019 Artisan Components, Inc.  All Rights Reserved.
--      
--      Use of this Software/Data is subject to the terms and conditions of
--      the applicable license agreement between Artisan Components, Inc. and
--      Taiwan Semiconductor Manufacturing Company Ltd..  In addition, this Software/Data
--      is protected by copyright law and international treaties.
--      
--      The copyright notice(s) in this Software/Data does not indicate actual
--      or intended publication of this Software/Data.
--------------------------------------------------------------------------
use std.all;
LIBRARY IEEE;
	use IEEE.std_logic_1164.all;
	use IEEE.VITAL_timing.all;
	use IEEE.VITAL_primitives.all;
	use WORK.vlibs.all; 
	use WORK.lib_cells_pkgs.all; 
	use work.rf2p_512x64_4_50_pkgs.all;

entity write_port_rf2p_512x64_4_50 is 
   generic(
        TIME_UNIT             		: TIME;
        TimingChecksOn	 		: boolean;
        PortName			: string;
        tipd_CLK              		: VitalDelayType01;
        tipd_D                		: VitalDelayArrayType01;
        tipd_A                		: VitalDelayArrayType01;
        tipd_CEN              		: VitalDelayType01;
        tperiod_CLK           		: VitalDelayType;
        tpw_CLK_negedge       		: VitalDelayType;
        tpw_CLK_posedge       		: VitalDelayType;
        tsetup_CEN_CLK_negedge_posedge   : VitalDelayType;
        tsetup_CEN_CLK_posedge_posedge   : VitalDelayType;
        thold_CEN_CLK_negedge_posedge    : VitalDelayType;
        thold_CEN_CLK_posedge_posedge    : VitalDelayType;
        tsetup_D_CLK_negedge_posedge     : VitalDelayArrayType;
        tsetup_D_CLK_posedge_posedge     : VitalDelayArrayType;
        thold_D_CLK_negedge_posedge      : VitalDelayArrayType;
        thold_D_CLK_posedge_posedge      : VitalDelayArrayType;
        tsetup_A_CLK_negedge_posedge     : VitalDelayArrayType;
        tsetup_A_CLK_posedge_posedge     : VitalDelayArrayType;
        thold_A_CLK_negedge_posedge      : VitalDelayArrayType;
        thold_A_CLK_posedge_posedge      : VitalDelayArrayType
   ); 
   port (
        A     : in std_logic_vector(8 downto 0);
        Am    : in std_logic_vector(8 downto 0);
        CEN   : in std_logic;
        CLK   : in std_logic;
        D     : in std_logic_vector(63 downto 0);
	MEM   : inout MEM_TYPE(511 downto 0, 63 downto 0);
        CLKWr : out std_logic
    );
    attribute VITAL_LEVEL1 of write_port_rf2p_512x64_4_50 : entity is TRUE;
end write_port_rf2p_512x64_4_50;

architecture BEHAVIORAL of write_port_rf2p_512x64_4_50 is
  constant ClkPort: 	string := cat("CLK", PortName);
  constant GtpPort: 	string := cat("GTP", PortName);
  constant InstPort: 	string := cat("rf2p_512x64_4_50_Port", PortName);
  signal CLKi		: std_logic;
  signal CLK_INT	: std_logic;
  signal CLK_MEM	: std_logic;
  signal GTPi		: std_logic;
  signal GTP_INT	: std_logic;
  signal ANi, ANBVio    : std_logic_vector(A'range);
  signal CENVio		: std_logic;
  signal TCEN_CEN_INT	: std_logic;
  signal CENi		: std_logic;
  signal Di,DataRd,DVio : std_logic_vector(D'range);
  signal NEQ_ADD      : std_logic;

	----------------------------------------------------------------------
Begin

TPW_CLK: TPwCell   generic map(tipd_clk=>tipd_CLK, tperiod_clk => tperiod_CLK,
                                tpw_clk_posedge => tpw_CLK_posedge, tpw_clk_negedge => tpw_CLK_negedge,
				TestSignalName=>ClkPort, HeaderMsg=>InstPort,
				TimingChecksOn=>TimingChecksOn)
                   port map(out0=>CLK_INT, clk=>CLK);
TA_A_UTI: for i in 0 to 8 generate
TCH_A: TchCellEdges   generic map(tipd_in0=>tipd_A(i), 
				tsetup_in0_clk_negedge_posedge => tsetup_A_CLK_negedge_posedge(i),
				tsetup_in0_clk_posedge_posedge => tsetup_A_CLK_posedge_posedge(i),
                                thold_in0_clk_negedge_posedge => thold_A_CLK_negedge_posedge(i), 
                                thold_in0_clk_posedge_posedge => thold_A_CLK_posedge_posedge(i), 
                                TestSignalName=>ClkPort, RefSignalName=>icat("A","",i), 
				TimingChecksOn=>TimingChecksOn, HeaderMsg=>InstPort)
                    port map(in0=>A(i), clk=>GTP_INT, Violation=>ANBVio(i),out0=>ANi(i));
end generate;                      

D_UTI: for i in 0 to 63 generate
 TCH_D: TchCellEdges   generic map(tipd_in0=>tipd_D(i), 
				tsetup_in0_clk_negedge_posedge => tsetup_D_CLK_negedge_posedge(i),
				tsetup_in0_clk_posedge_posedge => tsetup_D_CLK_posedge_posedge(i),
                                thold_in0_clk_negedge_posedge => thold_D_CLK_negedge_posedge(i), 
                                thold_in0_clk_posedge_posedge => thold_D_CLK_posedge_posedge(i), 
                                TestSignalName=>ClkPort, RefSignalName=>icat("D","",i), 
				TimingChecksOn=>TimingChecksOn, HeaderMsg=>InstPort)
                   port map(in0=>D(i), clk=>GTP_INT, Violation=>DVio(i),out0=>Di(i));

end generate; 
TCH_CEN: TchCellEdges   generic map(tipd_in0=>tipd_CEN, 
				tsetup_in0_clk_negedge_posedge => tsetup_CEN_CLK_negedge_posedge,
				tsetup_in0_clk_posedge_posedge => tsetup_CEN_CLK_posedge_posedge,
                                thold_in0_clk_negedge_posedge => thold_CEN_CLK_negedge_posedge, 
                                thold_in0_clk_posedge_posedge => thold_CEN_CLK_posedge_posedge, 
                                TestSignalName=>ClkPort, RefSignalName=>cat("CEN",PortName), 
				TimingChecksOn=>TimingChecksOn, HeaderMsg=>InstPort)
                    port map(in0=>CEN, clk=>CLK_INT, Violation=>CENVio,out0=>CENi);

---------------------------
Gtps: process(CLK_INT, CENi)
Begin
  if(CLK_INT'event and CLK_INT='0') then
    GTP_INT <= '0'; CLK_MEM <= '0'; 
  elsif((CENVio='X' and CENi='X') or (CLK_INT='X' and CENi = '0')) then
    GTP_INT <= 'X'; CLK_MEM <= 'X';
  elsif(CLK_INT'event and CLK_INT='1') then
    GTP_INT <= (not(CENi) or CLK_INT);
    CLK_MEM <= not(CENi);
  end if;
End process Gtps;
--   CLKWr <= CLK_MEM;

-------------- o O o -----------------
WriteMem : process(CLK_MEM, ANBVio, DVio)
    variable count, Lsb, Msb: integer;
    variable AddrVio, DataVio, MVio: boolean;
    variable NDi: std_logic_vector(D'Range);
    variable AddI: std_logic_vector(ANi'range);
  
    Begin
	if(Is_X(ANi)) then AddI:=(others => 'X');
        else AddI:=ANi; end if;
	AddrVio:= Is_X(ANBVio);
	DataVio:= Is_X(DVio);

        if(CLK_MEM'event or AddrVio or DataVio) then
          case CLK_MEM is
  	    when '1' => 		-- valid rising edge
              WRITE_MEM(AddI, Di, MEM);
	    when 'U'|'X' => 
	      WRITE_MEM(AddI, (Di'range => CLK_MEM), MEM) ;
	    when others  =>	null;
	  end case;
        end if;
end process WriteMem ;

Write_same: process ( Am, ANi, CLK_MEM)
   variable j : boolean := false;
   variable EQADD : std_ulogic := 'U';
Begin
  if ((CLK_MEM'last_active < 0.001 ns) and (CLK_MEM='1') and (Am = ANi)) then
      EQADD := '1';
  else
      EQADD := '0';
   end if;
CLKWr <= CLK_MEM and EQADD;
end process write_same;

end BEHAVIORAL ;

use std.all;
LIBRARY IEEE;
	use IEEE.std_logic_1164.all;
	use IEEE.VITAL_timing.all;
	use IEEE.VITAL_primitives.all;
	use WORK.vlibs.all; 
	use WORK.lib_cells_pkgs.all; 
	use work.rf2p_512x64_4_50_pkgs.all;

entity rf2p_512x64_4_50 is 
   generic(
        TIME_UNIT              : TIME  := 1.0 ns;
        TimingChecksOn	  : boolean := TRUE;
	tipd_AA: VitalDelayArrayType01(8 downto 0):=(others=>(0.000 ns, 0.000 ns));
	tipd_CLKA: VitalDelayType01:=(0.000 ns, 0.000 ns);
	tipd_CENA: VitalDelayType01:=(0.000 ns, 0.000 ns);
	tipd_AB: VitalDelayArrayType01(8 downto 0):=(others=>(0.000 ns, 0.000 ns));
	tipd_DB: VitalDelayArrayType01(63 downto 0):=(others=>(0.000 ns, 0.000 ns));
	tipd_CLKB: VitalDelayType01:=(0.000 ns, 0.000 ns);
	tipd_CENB: VitalDelayType01:=(0.000 ns, 0.000 ns);
	tsetup_AA_CLKA_negedge_posedge: VitalDelayArrayType(8 downto 0):=(others=>(1.000 ns));
	tsetup_AA_CLKA_posedge_posedge: VitalDelayArrayType(8 downto 0):=(others=>(1.000 ns));
	tsetup_CENA_CLKA_negedge_posedge: VitalDelayType:=1.000 ns;
	tsetup_CENA_CLKA_posedge_posedge: VitalDelayType:=1.000 ns;
	thold_AA_CLKA_negedge_posedge: VitalDelayArrayType(8 downto 0):=(others=>(0.500 ns));
	thold_AA_CLKA_posedge_posedge: VitalDelayArrayType(8 downto 0):=(others=>(0.500 ns));
	thold_CENA_CLKA_negedge_posedge: VitalDelayType:=0.500 ns;
	thold_CENA_CLKA_posedge_posedge: VitalDelayType:=0.500 ns;
	tsetup_AB_CLKB_negedge_posedge: VitalDelayArrayType(8 downto 0):=(others=>(1.000 ns));
	tsetup_AB_CLKB_posedge_posedge: VitalDelayArrayType(8 downto 0):=(others=>(1.000 ns));
	tsetup_DB_CLKB_negedge_posedge: VitalDelayArrayType(63 downto 0):=(others=>(1.000 ns));
	tsetup_DB_CLKB_posedge_posedge: VitalDelayArrayType(63 downto 0):=(others=>(1.000 ns));
	tsetup_CENB_CLKB_negedge_posedge: VitalDelayType:=1.000 ns;
	tsetup_CENB_CLKB_posedge_posedge: VitalDelayType:=1.000 ns;
	thold_AB_CLKB_negedge_posedge: VitalDelayArrayType(8 downto 0):=(others=>(0.500 ns));
	thold_AB_CLKB_posedge_posedge: VitalDelayArrayType(8 downto 0):=(others=>(0.500 ns));
	thold_DB_CLKB_negedge_posedge: VitalDelayArrayType(63 downto 0):=(others=>(0.500 ns));
	thold_DB_CLKB_posedge_posedge: VitalDelayArrayType(63 downto 0):=(others=>(0.500 ns));
	thold_CENB_CLKB_negedge_posedge: VitalDelayType:=0.500 ns;
	thold_CENB_CLKB_posedge_posedge: VitalDelayType:=0.500 ns;
        tsetup_CLKB_CLKA_posedge_posedge:  VitalDelayType := 0.50 ns;
        tsetup_CLKA_CLKB_posedge_posedge:  VitalDelayType := 0.50 ns;
	tpd_CLKA_QA: VitalDelayArrayType01(63 downto 0):=(others=>(1.0 ns,1.0 ns));
        tperiod_CLKA           : VitalDelayType  := 2.0 ns; -- min cycle time
        tperiod_CLKB           : VitalDelayType  := 2.0 ns; -- min cycle time
        tpw_CLKA_negedge       : VitalDelayType  := 1.0 ns;
        tpw_CLKA_posedge       : VitalDelayType  := 1.0 ns;
        tpw_CLKB_negedge       : VitalDelayType  := 1.0 ns;
        tpw_CLKB_posedge       : VitalDelayType  := 1.0 ns
   ); 
   port (
	AA: in std_logic_vector(8 downto 0);
	CLKA: in std_logic;
	CENA: in std_logic;
	AB: in std_logic_vector(8 downto 0);
	DB: in std_logic_vector(63 downto 0);
	CLKB: in std_logic;
	CENB: in std_logic;
	QA: out std_logic_vector(63 downto 0)
    );
	attribute VITAL_LEVEL1 of rf2p_512x64_4_50 : entity is TRUE;
end rf2p_512x64_4_50;

architecture BEHAVIORAL of rf2p_512x64_4_50 is
  signal MEM   : MEM_TYPE(511 downto 0, 63 downto 0);
  signal CLKWr : std_logic;
  signal Am : std_logic_vector(8 downto 0);
	----------------------------------------------------------------------
Begin
  PortA: read_port_rf2p_512x64_4_50 
    generic map (
	TIME_UNIT=> TIME_UNIT,
	TimingChecksOn=> TimingChecksOn,
	PortName=>"A",
	tipd_A=>tipd_AA,
	tipd_CLK=>tipd_CLKA,
	tipd_CEN=>tipd_CENA,
	tsetup_A_CLK_negedge_posedge=>tsetup_AA_CLKA_negedge_posedge,
	tsetup_A_CLK_posedge_posedge=>tsetup_AA_CLKA_posedge_posedge,
	tsetup_CEN_CLK_negedge_posedge=>tsetup_CENA_CLKA_negedge_posedge,
	tsetup_CEN_CLK_posedge_posedge=>tsetup_CENA_CLKA_posedge_posedge,
	thold_A_CLK_negedge_posedge=>thold_AA_CLKA_negedge_posedge,
	thold_A_CLK_posedge_posedge=>thold_AA_CLKA_posedge_posedge,
	thold_CEN_CLK_negedge_posedge=>thold_CENA_CLKA_negedge_posedge,
	thold_CEN_CLK_posedge_posedge=>thold_CENA_CLKA_posedge_posedge,
	tsetup_CLK_CLKWr_posedge_posedge=> tsetup_CLKA_CLKB_posedge_posedge,
	thold_CLK_CLKWr_posedge_posedge=> tsetup_CLKB_CLKA_posedge_posedge,
	tpd_CLK_Q=>tpd_CLKA_QA, 
	tperiod_CLK=> tperiod_CLKA,
	tpw_CLK_negedge=> tpw_CLKA_negedge,
	tpw_CLK_posedge=> tpw_CLKA_posedge
   )
    port map (
	A=> AA,
	Am=> Am,
	CEN=> CENA,
	CLK=> CLKA,
	CLKWr=> CLKWr,
	Q=> QA,
	MEM=> MEM
);
	
  PortB: write_port_rf2p_512x64_4_50 
    generic map (
	TIME_UNIT=> TIME_UNIT,
	TimingChecksOn=> TimingChecksOn,
	PortName=>"B",
	tipd_A=>tipd_AB,
	tipd_D=>tipd_DB,
	tipd_CLK=>tipd_CLKB,
	tipd_CEN=>tipd_CENB,
	tsetup_A_CLK_negedge_posedge=>tsetup_AB_CLKB_negedge_posedge,
	tsetup_A_CLK_posedge_posedge=>tsetup_AB_CLKB_posedge_posedge,
	tsetup_D_CLK_negedge_posedge=>tsetup_DB_CLKB_negedge_posedge,
	tsetup_D_CLK_posedge_posedge=>tsetup_DB_CLKB_posedge_posedge,
	tsetup_CEN_CLK_negedge_posedge=>tsetup_CENB_CLKB_negedge_posedge,
	tsetup_CEN_CLK_posedge_posedge=>tsetup_CENB_CLKB_posedge_posedge,
	thold_A_CLK_negedge_posedge=>thold_AB_CLKB_negedge_posedge,
	thold_A_CLK_posedge_posedge=>thold_AB_CLKB_posedge_posedge,
	thold_D_CLK_negedge_posedge=>thold_DB_CLKB_negedge_posedge,
	thold_D_CLK_posedge_posedge=>thold_DB_CLKB_posedge_posedge,
	thold_CEN_CLK_negedge_posedge=>thold_CENB_CLKB_negedge_posedge,
	thold_CEN_CLK_posedge_posedge=>thold_CENB_CLKB_posedge_posedge,
	tperiod_CLK=> tperiod_CLKB,
	tpw_CLK_negedge=> tpw_CLKB_negedge,
	tpw_CLK_posedge=> tpw_CLKB_posedge
    )
    port map (
	CLK=> CLKB,
	A=> AB,
	Am=> Am,
	CEN=> CENB,
	D=> DB,
	MEM=> MEM,
	CLKWr=> CLKWr
);
end BEHAVIORAL ;

