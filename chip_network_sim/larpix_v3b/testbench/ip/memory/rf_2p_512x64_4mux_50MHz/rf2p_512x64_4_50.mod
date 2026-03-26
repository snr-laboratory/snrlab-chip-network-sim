/*
 *      CONFIDENTIAL AND PROPRIETARY SOFTWARE/DATA OF ARTISAN COMPONENTS, INC.
 *      
 *      Copyright (c) 2019 Artisan Components, Inc.  All Rights Reserved.
 *      
 *      Use of this Software/Data is subject to the terms and conditions of
 *      the applicable license agreement between Artisan Components, Inc. and
 *      Taiwan Semiconductor Manufacturing Company Ltd..  In addition, this Software/Data
 *      is protected by copyright law and international treaties.
 *      
 *      The copyright notice(s) in this Software/Data does not indicate actual
 *      or intended publication of this Software/Data.
 *      name:			RF-2P-HS Register File Generator
 *           			TSMC CL018G Process
 *      version:		2003Q2V2
 *      comment:		
 *      configuration:	 -instname "rf2p_512x64_4_50" -words 512 -bits 64 -frequency 50 -ring_width 10 -mux 4 -drive 3 -write_mask off -wp_size 8 -top_layer met6 -power_type rings -horiz met3 -vert met2 -cust_comment "" -left_bus_delim "[" -right_bus_delim "]" -pwr_gnd_rename "VDD:VDD,GND:VSS" -prefix "" -pin_space 0.0 -name_case upper -check_instname on -diodes on -inside_ring_type GND
 *
 *      Synopsys model for Synchronous Dual-Port Register File
 *
 *      Library Name:   aci
 *      Instance Name:  rf2p_512x64_4_50
 *      Words:          512
 *      Word Width:     64
 *      Mux:            4
 *      Pipeline:       No
 *      Process:        typical
 *      Delays:		max
 *
 *      Creation Date:  2019-02-18 16:41:55Z
 *      Version:        2003Q2V2
 *
 *      Verified With: Synopsys Primetime
 *
 *      Modeling Assumptions: This library contains a black box description
 *          for a memory element.  At the library level, a
 *          default_max_transition constraint is set to the maximum
 *          characterized input slew.  Each output has a max_capacitance
 *          constraint set to the highest characterized output load.
 *          Different modes are defined in order to disable false path
 *          during the specific mode activation when doing static timing analysis. 
 *
 *
 *      Modeling Limitations: This stamp does not include power information.
 *          Due to limitations of the stamp modeling, some data reduction was
 *          necessary.  When reducing data, minimum values were chosen for the
 *          fast case corner and maximum values were used for the typical and
 *          best case corners.  It is recommended that critical timing and
 *          setup and hold times be checked at all corners.
 *
 *      Known Bugs: None.
 *
 *      Known Work Arounds: N/A
 *
 */

MODEL
MODEL_VERSION "1.0";
DESIGN "rf2p_512x64_4_50";
OUTPUT QA[63:0];
INPUT AA[8:0];
INPUT AB[8:0];
INPUT CENA;
INPUT CENB;
INPUT CLKA;
INPUT CLKB;
INPUT DB[63:0];
MODE mem_modeA = MissionA  COND(CENA==0), 
                 InactiveA COND(CENA==1);
MODE mem_modeB = MissionB  COND(CENB==0), 
                 InactiveB COND(CENB==1);
tch_tasa: SETUP(POSEDGE) AA CLKA MODE(mem_modeA=MissionA);
tch_taha: HOLD(POSEDGE)  AA CLKA MODE(mem_modeA=MissionA);
tch_tasb: SETUP(POSEDGE) AB CLKB MODE(mem_modeB=MissionB);
tch_tahb: HOLD(POSEDGE)  AB CLKB MODE(mem_modeB=MissionB);
tch_tcsa: SETUP(POSEDGE) CENA CLKA ;
tch_tcha: HOLD(POSEDGE) CENA CLKA ;
tch_tcsb: SETUP(POSEDGE) CENB CLKB ;
tch_tchb: HOLD(POSEDGE) CENB CLKB ;
tch_tdsb: SETUP(POSEDGE) DB CLKB MODE(mem_modeB=MissionB);
tch_tdhb: HOLD(POSEDGE) DB CLKB MODE(mem_modeB=MissionB);
period_tcyca: PERIOD(POSEDGE) CLKA ;
tpw_tckha: WIDTH(POSEDGE) CLKA ;
tpw_tckla: WIDTH(NEGEDGE) CLKA ;
period_tcycb: PERIOD(POSEDGE) CLKB ;
tpw_tckhb: WIDTH(POSEDGE) CLKB ;
tpw_tcklb: WIDTH(NEGEDGE) CLKB ;
tch_tccA: SETUP(POSEDGE) CLKA CLKB ;
tch_tccB: SETUP(POSEDGE) CLKB CLKA ;
dly_tya: DELAY(POSEDGE) CLKA QA  MODE(mem_modeA=MissionA);
ENDMODEL
