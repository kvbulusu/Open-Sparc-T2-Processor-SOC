set DV_ROOT /projects/sparc/OpenSPARCT2

set rtl_files [ glob $DV_ROOT/*/*/*.v ]
set include_paths {
-include $DV_ROOT/sys/iop/dmu/rtl
-include $DV_ROOT/sys/iop/pcie_common/rtl
-include $DV_ROOT/sys/iop/niu/rtl
}

config message level VER-61 off
config message level VLOG-457 off
config message level VLOG-90 off
config message level VLOG-188 warning
config message level BND-18 warning
config message limit VLOG-457 1
config message limit VLOG-90 1
config message limit VLOG-101 1
config message level RTL-90 warning
config message level RTL-2027 off
config message level VLOG-102 warning
config message level VLOG-7 warning
config rtl verilog 2000 on
#config rtl LRM_version IEEE_1800_2005
set SCRPATH scripts
set l /std_cell_lib
#set design cpu
#set design ccu
#set m /work/$design/$design

if { ![data exists $l ] } {
import volcano  45nm_7m_std_cell_library.volcano
source $SCRPATH/patch_lib.tcl
clear readonly $l
}

set spare 0
set enforce_input_fanout_one     0
set allow_outport_drive_innodes  1
set add_lockup_latch 1
config rtl verilog 2000 on
config map clockedge on
config rtl datapath physical off
config timing inout cell off
config timing threshold slew 25 55 45 75
config timing clockgating on
config timing inout net on
config timing slew default generation on
config sdc unit capacitance p
config sdc unit resistance k
config sdc unit time n
config timing clock multiple on
config timing borrow method relax
config timing borrow automatic on
config timing slew mode largest
config timing propagate constants combinational
config timing check recovery on
config rtl clockgate on -integrated $l/CKLHQD16BWP
config view directory  block_views
config volcano -crash.volcano off
config snap error_volcano off

### For snap volcano, only output work lib to save disk space
config snap procedure “volcano” {
if { [data exists /macro_lib ] } {
export volcano $outputPrefix.volcano -object /work -object /macro_lib
} else  {
export volcano $outputPrefix.volcano -object /work
}
}

config message limit LC-21 1
config message level CK-23 warning
config message level CK-347 warning
config message level TA-280 warning
config message level RTL-2027 info
config message level LC-73 info
config message level LAVA-976 info
config message level CK-41 info
config message level NAM-4 info
config message level CZ-10 info
config message level WIRE-9 info
config message level OPTO-171 info
config message level OPTO-169 info
config message level CK-26 info
config message level SWP-8 info
config message level BLKB-102 off
config message level RTL-71 warning
config timing derate cell 1.2 -case worst -late -type data
config message limit SWP-8 1
config message limit MAP-111 1
config message level CND-102 off

config dft scan shift_register on
config gate clockgate off
config primary unique off
#config timing flatten buffer $l/BUF_2/BUF_2_HYPER
config optimize fanout -fanout_limit 16

config snap procedure post-fix-netlist {
### report high-fanout nets
config report clone {PROBLEM CAUSE SINK SLACK MODEL_NAME PIN_NAME NET_NAME}
report clone $m -problem -trace -number 100 -file snap/clone.rpt
}

config snap output on [config snap level] post-fix-netlist fix-netlist-final

## Config timing report
config snap procedure fix-time-rpt {
config report timing detail {PIN_NAME PIN_DIR SINK AT RT SLACK EDGE CLOCK_FLAG PRIMARY_PHASE PHASE}
config report timing path {PIN_NAME:50 MODEL_NAME DELAY SLEW AT SLACK ADAPTIVE_BUFFERS PIN_LOAD WIRE_LOAD SINK}
}

config snap output on [config snap level] fix-time-rpt fix-time-start

#Fix Cell Snap Procedures
config snap procedure mcpu {
config multithread -thread auto -feature route -gr on
config multithread -thread auto -feature all
}

proc luniq {L} {
# removes duplicates without sorting the input list
set t {}
foreach i $L {if {[lsearch -exact $t $i]==-1} {lappend t $i}}
return $t
} ;# RS

proc block_syn {mod} {
global rtl_files rtl_files1  rtl_files2  rtl_files3  rtl_files4  rtl_files5
global DV_ROOT l design m SCRPATH spare
global enforce_input_fanout_one allow_output_drive_innodes add_lockup_latch element

message info SPLC-1 “n Now synthesizing $mod …stay tuned..n”
set default_clk_transition  0.05
set default_hold_skew  0.0
set default_setup_skew  0.0
set default_clk_transition  0.05
set ideal_net_list { cmp_gclk_c2_ccx_left cmp_gclk_c2_ccx_right }
set false_path_list {}
set max_transition   0.15
set max_fanout         6
# default input/output delays
set default_input_delay  0.15
set default_output_delay 0.2
set default_clk gclk
set clk_name_list [list]
set ideal_inputs [list]
set design $mod
set m /work/$mod/$mod
if { ![data exists $m ] } {
eval import rtl -verilog -analyze  $include_paths $rtl_files $rtl_files

if { $spare == 1 } {
eval run rtl elaborate $design -spare register -arithmetic auto

config report rtl registers -latches off -clock off -tri off -output off -fileinfo off -range off -sync off -async off -range off -header off -summary off -details on -usermodel_only on
data loop le lib_entity /work {
data loop em entity_model $le {
set spare_reg  [ report rtl registers $em -string -noheader  ]
foreach sp $spare_reg {
if { [data exists $em/$sp ] && [regexp  “cell” [data get $em/$sp type] ]} {
if {[query rule model $em -type] eq “standard”} {
force rtl spare_register on $em/$sp
force keep $em/$sp
message info OST-1 “Applied spare_reg attr on $em/$sp and preserved the spare register”
}
}
}
}
}

} else {
eval run rtl elaborate $design  -arithmetic auto

}
}

config message level POPT-2 warning
config message level POPT-3 warning
config multithread -thread auto -feature all

fix rtl $m

enwrap {
if { [data exists /work/clock_multiplier_10x ] } {
data delete object /work/clock_multiplier_10x
run gate sweep $m -hier
}
} remove-clock-mult-${design} $m

config async concur off
set all_libs [data list root_lib / ]
set all_libs [lsearch -all -inline -not $all_libs /work ]
set all_libs [lsearch -all -inline -not $all_libs /macro_lib ]
set all_work_libs [data find / work* -type lib ]
eval “run bind logical -no_uniquify $m $all_libs ”

enwrap {
run prepare blackbox stub $m
} prepare-stubs $m

run prepare blackbox stub $m

config sweep sequential on -keep_float off -cycle on

force dft scan style $m muxed_flip_flop
config snap replace [config snap level] fix-netlist-sweep ” run gate sweep $m -hier -cross_boundary ”

fix netlist $m $l -effort high -scan

set clk_port_pin [lindex $element 0 ]
set clk_name [lindex $element 0 ]
set clk_freq [lindex $element 1 ]
set setup_skew [lindex $element 2 ]
set hold_skew [lindex $element 3 ]
set clock_transition [lindex $element 4 ]
set clk_is_port 1
set clk_exists [data find $m ${clk_port_pin} -regexp -type mpin]
lappend ideal_inputs $clk_name
set clk_period [expr 1000.0 / $clk_freq / 1.0]
set high_time [expr $clk_period / 2.0]

if { [data get $m name] == “ccx” } {
force timing clock $m/$clk_port_pin ${clk_period}ns -waveform [list -rise 0ns -fall ${high_time}ns ] -name $clk_name
force timing clock $m/cmp_gclk_c2_ccx_right ${clk_period}ns -waveform [list -rise 0ns -fall ${high_time}ns ] -name cmp_gclk_c2_ccx_right
force timing margin setup ${setup_skew}ns -to [data find $m $clk_name -regexp -type mpin]
force timing margin hold ${hold_skew}ns -to [data find $m $clk_name -regexp -type mpin]
force timing slew [data find $m $clk_name -regexp -type mpin] ${clock_transition}ns
force timing margin setup ${setup_skew}ns -to [data find $m cmp_gclk_c2_ccx_right -regexp -type mpin]
force timing margin hold ${hold_skew}ns -to [data find $m cmp_gclk_c2_ccx_right -regexp -type mpin]
force timing slew [data find $m cmp_gclk_c2_ccx_right -regexp -type mpin] ${clock_transition}ns
} elseif { [data get $m name ] == “mcu” } {
set mcu_ck_pin_list ” drl2clk l2clk iol2clk”
foreach ck $mcu_ck_pin_list {
set clk_name $ck
if { $clk_name == “drl2clk” || $clk_name ==  “iol2clk” } {
force timing clock $m/$ck ${clk_period}ns -waveform [list -rise 0ns -fall ${high_time}ns ] -virtual  } else {
force timing clock $m/$ck 700ps -waveform [list -rise 0ns -fall 350ps ] -virtual  }

force timing margin setup ${setup_skew}ns -to [data find $m $clk_name -regexp -type mpin]
force timing margin hold ${hold_skew}ns -to [data find $m $clk_name -regexp -type mpin]
force timing slew [data find $m $clk_name -regexp -type mpin] ${clock_transition}ns
}
} else {
force timing clock $m/$clk_port_pin ${clk_period}ns -waveform [list -rise 0ns -fall ${high_time}ns ] -name $clk_name

force timing margin setup ${setup_skew}ns -to [data find $m $clk_name -regexp -type mpin]
force timing margin hold ${hold_skew}ns -to [data find $m $clk_name -regexp -type mpin]
force timing slew [data find $m $clk_name -regexp -type mpin] ${clock_transition}ns

}
set non_ideal_inputs [list]
set Inputs [data list “model_pin -direction in” $m]
set Inputs [concat $Inputs [data list “model_pin -direction inout” $m ]]

foreach input_object $Inputs {
set input_name [data get $input_object name]
set input_is_ideal [lsearch -exact $ideal_net_list $input_name]
if {$input_is_ideal == -1} {
lappend non_ideal_inputs $input_name
} else {
lappend ideal_inputs $input_name
}
}

foreach iport $non_ideal_inputs {
force timing delay $m/$clk_name $iport -time ${default_input_delay}ns
}

set Outputs [data list “model_pin -direction out” $m ]
foreach oport $Outputs {
force timing check $m/$clk_name $oport -time ${default_output_delay}ns
}

data loop oport “model_pin -direction out” $m {
force timing check $m/$clk_name $oport -time ${default_output_delay}ns
}

if {[info exists false_path_list] && ($false_path_list != {}) } {
foreach fp $false_path_list {
force timing false -through $fp }
}

if {[info exists enforce_input_fanout_one] && ($enforce_input_fanout_one  == 1)} {
foreach fo $non_ideal_inputs {
force limit fanout $fo 1
}
}

enwrap {
set sweep_model “”
force undriven $m 0
run gate sweep $m -hier -cross_boundary
if { [query undriven $m  ] != “” } {
foreach obj [query undriven $m ] {
if { [regexp pin [data get $obj type ] ] } {
lappend sweep_model [data get [data list pin_model $obj ] name ]
} else {
lappend sweep_model [data get [data list net_model $obj ] name ]
}
}
set smod [luniq [lsort $sweep_model ] ]
}
if { [info exists smod ] && $smod != “” } {
foreach mobj $smod {
set sweep_mobj_tmp [ data find /work $mobj -regexp -hier -type model ]
foreach sweep_mobj $sweep_mobj_tmp {
force undriven $sweep_mobj  0
run gate sweep $sweep_mobj
}
}
unset smod
}
} sweep-subblk-${mod} $m

enwrap {
run timing adjust endpoint $m -external
} adjust-endpoints-b4-ftime-${mod} $m

enwrap {
data loop mp “model_pin” $m {
if { [data count pin_net $mp] != 0 } {
run gate buffer pin $m $l $mp }
}

data loop mp “model_pin -direction out” $m {
if { [data count pin_net $mp] != 0 } {
run gate buffer pin $m $l $mp }
}

# set this switch to 0 to make sure output port doesn’t driving internal nodes
if {[info exists allow_outport_drive_innodes] && ($allow_outport_drive_innodes == 0)} {
#set_isolate_ports -type inverter [all_outputs]
force buffer setup $m -inverter only
data loop mp “model_pin -direction out” $m {
if { [data count pin_net $mp] != 0 } {
run gate buffer pin $m $l $mp
}
}
clear buffer setup $m
}

}   buffer-b4-fixtime-${mod} $m

fix time $m $l -effort high -timing_effort high -size

enwrap {
data flatten $m -rtl_inferred_models
export volcano fullViews/${design}_full.volcano -object $m

set m1 $m
set modelName  [lindex [split $m1 /] 3]
force model view $m1 fixtime
export view $m1  -force
run prepare glassbox abstract $m1 -modeling timing

} gb-extract-${mod} $m
lappend blk_with_views_final $mod

if { [data exists /work ] } {
data delete object /work }
if { [data exists /macro_lib ] } {
data delete object /macro_lib
}
}

set blk_list ” ccu ccx dmu db0 db1 efu l2b l2t ncu rst sii sio spc tcu mcu rdp tds mac rtx”

foreach mod $blk_list {
switch $mod {
ccu   {
set element  {gclk    1400.0   0.000   0.000   0.05}
block_syn $mod
}
dmu  {
set element  {gclk    350.0   0.000   0.000   0.05}
block_syn $mod
}
ccx  {
set element {cmp_gclk_c2_ccx_left    1400.0   0.000   0.000   0.05}
block_syn $mod
}
db0  {
set element {gclk    1400.0   0.000   0.000   0.05}
block_syn $mod
}
db1  {
set element { gclk    1400.0   0.000   0.000   0.05}
block_syn $mod
}
efu  {
set element  { gclk         1400.0   0.000   0.000   0.05}
block_syn $mod
}
l2b  {
set element {gclk           1400.0   0.000   0.000   0.05}
block_syn $mod
}
l2t   {
set element { gclk           1400.0   0.000   0.000   0.05}
block_syn $mod
}
ncu  {
set element {gclk           350.0   0.000   0.000   0.05}
block_syn $mod
}
rst {
set element { gclk           350.0   0.000   0.000   0.05}
block_syn $mod
}
sii  {
set element {  gclk           350.0   0.000   0.000   0.05}
block_syn $mod
}
sio {
set element { gclk           350.0   0.000   0.000   0.05}
block_syn $mod
}
spc {
set element { gclk           1400.0   0.000   0.000   0.05}
block_syn $mod
}
tcu  {
set element { gclk           350.0   0.000   0.000   0.05}
block_syn $mod
}
mcu  {
set element {  iol2clk           400.0   0.000   0.000   0.05}
block_syn $mod
}
rdp  {
set element { cmp_gclk_c0_rdp    1500.0   0.000   0.000   0.05}
block_syn $mod
}
tds  {
set element { cmp_gclk_c0_tds   1500.0   0.000   0.000   0.05}
block_syn $mod
}
mac {
set element  {cmp_gclk_c1_mac    1500.0   0.000   0.000   0.05}
block_syn $mod
}

rtx  {
set element { cmp_gclk_c0_rtx    1500.0   0.000   0.000   0.05}
block_syn $mod
}
}
}

message info OST-4 ” Block Level Synthesis is done..n”

return
