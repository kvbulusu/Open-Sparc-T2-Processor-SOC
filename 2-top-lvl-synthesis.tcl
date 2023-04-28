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

set SCRPATH /projects/sparc/OpenSPARCT2/scripts
set l /std_cell_lib
set design cpu
#set design ccu
set m /work/$design/$design

if { ![data exists $l ] } {
import volcano  45nm_7m_std_cell_library.volcano
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

config snap procedure hier_uniquify {
global m
foreach tmp [ data list model_cell $m ] {
if { [data list cell_model $tmp ] == “” } {
data uniquify $m -cell $tmp
} else {
data uniquify $m -entity [data list model_entity [data list cell_model $tmp ] ]

}
}
}

if { ![data exists $m ] } {
eval import rtl -verilog -analyze $include_paths $rtl_files

}
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

fix rtl $m

foreach v $blk_with_views_final {
import volcano [query view directory ]/work/$v/$v/fixtime.volcano -merge
force keep /work/$v/$v -content
}

run prepare blackbox stub $m
run bind logical -no_uniquify $m $l /work

fix netlist $m $l -effort high -scan
force maintain $m -hier

fix time $m $l -timing_effort high -effort high -slack 0ps  -size

################################################################################
##### Delete the glass boxes
################################################################################
export volcano $snapdir/${design}%fix_time_glass.volcano
foreach v $blk_with_views_final {
data delete object /work/$v/$v
}

################################################################################
##### Import the full designs
################################################################################
import volcano ./fullViews/or1200_cpu_full.volcano      -merge
import volcano ./fullViews/or1200_dmmu_top_full.volcano -merge
import volcano ./fullViews/or1200_immu_top_full.volcano -merge

foreach v $blk_with_views_final {
import volcano ./fullViews/$v_full.volcano -merge
}
run bind logical $m $l
run bind logical $m /work
check design $m -file $snapdir/${design}_postFixtime_check_design.rpt
# Use enwrap to dump reports and volcanoes
enwrap {} undo-glassbox $m

enwrap {
config hierarchy separator “_”
data flatten $m
} flatten-design-postftime $m

############################################
# Scan Insertion for full chip
#Optionally one can use the Scan insertion script below at block level/bottom-up synthesis and do top level scan insertion while doing top level #integration.
############################################
enwrap {

if { [info exists add_lockup_latch ] && ($add_lockup_latch == 1) } {
config dft scan lockup on
}
config dft scan shift_register on
config dft setup clock_groups on
config dft scan chain_mix clock on
config dft repair violation clock_violation on
config dft repair violation comb_loop on
config dft repair violation disable_tribus on
config dft repair violation latch on
config dft repair violation reset_violation on

force dft scan clock $m [list $m/mpin:$clk_name]
force dft scan control $m $m/mpin:$scanenable_port scan_enable
for {set sid 0} {$sid < $chain_count } {incr sid} {
data create port [data only model_entity $m] SI${sid} -direction in
data create port [data only model_entity $m] SO${sid} -direction out
force dft scan chain $m $sid SI${sid} SO${sid}
}
} scan_setup $m

enwrap {
run dft check $m -pre_scan
} pre-scan-check $m
enwrap {
run dft scan insert $m
} scan-insertion $m
enwrap {
run dft check $m -post_scan
} post-scan-check $m
enwrap {
run dft scan trace $m
} scan-trace $m

enwrap {
data flatten $m -rtl_inferred_models
export volcano snap/${design}_full.volcano -object $m

set m1 $m
set modelName  [lindex [split $m1 /] 3]
force model view $m1 fixtime
export view $m1  -force
run prepare glassbox abstract $m1 -modeling timing

puts “Bottom up synthesis done for $design ”
} gen-gb-views-ftime $m

return
