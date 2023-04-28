#############################################
### Template Script
#######################################################################################

### Design Import & Parameters ###

set design rtx
set m /work/${design}/${design}
set l /std_cell_lib
#If you are reading netlist, change this to 1 and set the netlist dir
set netlist 0
set netlist_dir ./blk-level-synthesis

if { ![data exists $l ] } {
import volcano  45nm_7m_std_cell_library.volcano
}

if { $netlist == “0″ && [data exists $m ] == “0″ } {
import volcano rtx%fix-time-final.volcano
} else {
import netlist $netlist_dir/rtx%fix-time-final%verilog.v

}

config multithread -thread auto -feature timer
config multithread -thread auto -feature delay
config multithread -thread auto -feature optimization
config multithread -thread auto -feature route -gr on
config prepare hyper on
force delay adaptive_buffering $m on -hierarchical on

clear readonly $l
run prepare hyper $l

config volcano -crash.volcano off
config snap error_volcano off
config message level TA-280 warning
### For snap volcano, only output work lib to save disk space
config snap procedure “volcano” {
if { [data exists /macro_lib ] } {
export volcano $outputPrefix.volcano.tar.gz -object /work -object /macro_lib
} else  {
export volcano $outputPrefix.volcano.tar.gz  -object /work
}
}

config snap output on [config snap level ] volcano rhy-*
config snap output on [config snap level ] volcano fix-clock-proto-final
config snap output on [config snap level ] volcano fix-clock-hier-final
config snap output on [config snap level ] volcano fix-budget-setup-buffer-final
config snap output on [config snap level ] volcano fix-budget-buffer-final
config snap output on [config snap level ] volcano fix-budget-final

set all_libs [data list root_lib / ]
set all_libs [lsearch -all -inline -not $all_libs /work ]
set all_libs [lsearch -all -inline -not $all_libs /macro_lib ]
eval “run bind logical $m $all_libs ”

enwrap {
source -echo $data_dir/clear_clk_magma.tcl

force undriven $m 0

if { [regexp fix-time-final [query snap history $m ] ] } {
message info OPST-1 “Fix time is already done..so skipping this step n”
} else {

foreach tmp [data list model_cell $m ]  {
if { [regexp “/work/” [data list cell_model $tmp ] ] } {
lappend ckeep [data only cell_model $tmp ]
force keep [data only cell_model $tmp ] -content
message info OPST-1 “force keep applied on sub block [data only cell_model $tmp ]”
}
}

config snap replace [config snap level ] fix-time-run-gate-clockgate “”
config snap replace [config snap level] fix-time-speed-* “run gate speed $m $l -effort low”
config snap replace [config snap level] fix-time-rof* “”
config snap replace [config snap level ] fix-time-optimize-strength-speed  “run optimize strength $m $l -prototype ”
run timing adjust endpoint $m -external
run gate sweep $m -hier -cross_boundary

fix time $m $l -effort low -timing_effort low

foreach tmp $ckeep {
clear keep $tmp -content
message info OPST-2 “clear kept sub block $tmp”
}
set bufferl [data list model_cell_leaf -attr {repeater_reason 6} $m]
puts “destroy_all_assign_buffers: Unkeeping buffers, entities”
data loop c model_cell_leaf -attr {repeater_reason 6} $m {
clear keep $c
clear keep [data only cell_model $c]
}

puts “destroy_all_assign_buffers: Removing [llength $bufferl] buffers”
run gate unbuffer $m $l -cell $bufferl
set bufferl [data list model_cell_leaf -attr {repeater_reason 6} $m]
puts “destroy_all_assign_buffers: [llength $bufferl] buffers remain”

} rhy-initial-setup $m

#Set this variable to 1 , if you have stubs as opposed to full netlist.
set bbox 0
set scan 0

if { $bbox == “1″} {
### Specify Blackbox Floorplan Parameters (OPTIONAL) ###
report blackbox cells $m
run plan uninitialize blackbox $m/<sub_blks>
rule model /work/sub_blk/sub_blk -type no_type
report blackbox cells $m
force blackbox parameters /work/sub_blk/sub_blk -width 1150u -height 375.9u
run plan initialize blackbox $m -replace
force location cell “$m/sub_blk” floating ;# temporary, to enable move
run plan move cell “$m/sub_blk” { 307.175u 297.765u  } EAST
force location cell “$m/sub_blk” fixed
report blackbox cells $m

}
### Perform Scan Tracing (OPTIONAL) ###

enwrap {
if { $scan == “1″} {
config scan optimize $m -hierarchy on
run dft scan trace $m
}
} rhy-scan-trace $m

### Create Power Domains (OPTIONAL) ###
enwrap {
force library rail $l VDD12
force library rail $l VSS
set pgn VSS
data loop ent lib_entity $l {
data loop port entity_port $ent {
if {[data get $port name]==$pgn} {
message info OPST-1 “Assigning rail $pgn to port $port of $ent.”
rule port use $port ground -rail VSS
}
}
}

set pgn VDD12
data loop ent lib_entity $l {
data loop port entity_port $ent {
if {[data get $port name]==$pgn} {
message info OPST-1 “Assigning rail $pgn to port $port of $ent”
rule port use $port power -rail VDD12
}
}
}

data create domain $m default
set dom1 [ data list model_domain $m ]
force domain primary /work/$design/$design/domain:default
force domain process /work/$design/$design/domain:default 1.000000 -case best
force domain process /work/$design/$design/domain:default 1.000000 -case worst
force domain temperature /work/$design/$design/domain:default -40.000000 -case best
force domain temperature /work/$design/$design/domain:default 125.000000 -case worst
force domain net /work/$design/$design/domain:default VSS ground -primary -supply_type constant
force domain voltage /work/$design/$design/domain:default VSS 0.000000 -case best
force domain voltage /work/$design/$design/domain:default VSS 0.000000 -case worst
force domain rail /work/$design/$design/domain:default VSS /std_cell_lib VSS
force domain net /work/$design/$design/domain:default VDD12 power -primary -supply_type constant
force domain voltage /work/$design/$design/domain:default VDD12 1.260000 -case best
force domain voltage /work/$design/$design/domain:default VDD12 1.080000 -case worst
force domain rail /work/$design/$design/domain:default VDD12 /std_cell_lib VDD12
force derate method user -domain /work/$design/$design/domain:default

data loop fp model_floorplan $m {
data attach $fp floorplan_domain $dom1
}
run domain apply $m -create_mpins
clear readonly $l
run prepare hyper $l -domain $dom1

} rhy-domain $m

# Tie cell connection (OPTIONAL)
# run gate tiecell with local_tie_off

### Create Initial Top-Level Floorplan ###
enwrap {
data create floorplan $m $design
data attach $m/floorplan:$design floorplan_domain $dom1
#force floorplan parameters $m/floorplan:$design -width 2350u -height 2350u -left_margin 250u -right_margin 250u -top_margin 250u -bottom_margin 250u
run floorplan size $m/floorplan:$design -target_total_util 0.6 -aspect_ratio 1
#The above command will create the following parameters
#force floorplan parameters {/work/$design/$design/floorplan:$design} -width 0.01376346 -height 0.01376346 -left_margin 445u -right_margin 445u -bottom_margin 450u -top_margin 375u
run floorplan apply $m -allow_wayward -bucket_size 2_cellrow
} rhy-fp $m

enwrap {
### Create Pad Ring ###
run plan create padring $m -automatic cell_name
} rhy-pad $m

### Place Macros & Logic Clusters ###

enwrap {
run plan create pin $m
run place cluster $m -timing_effort medium -macro_style overlapping -effort low

} rhy-icp-1 $m

### Auto Partitioning
enwrap {

config partition allow_clock_output on
config partition effort high
config partition floorplans_outside off
config partition max_cell_count 350000
config partition min_cell_count 90000
config partition optimize pin_count on
config partition optimize size_balance on
#Before below place corr config is set, make sure design is placed using initial cluster pl otherwise it will issue fatal error
config partition optimize placement_corr on

run plan partition auto $m

## Check whether the partitioning is complete or not?
check plan partition $m -complete

report plan partition candidates $m
} rhy-auto-partition $m

enwrap {

# Commit hierarchy
run plan hierarchy commit $m -no_overlay
} rhy-hier-commit $m

### Specify Design-Wide Shaping Parameters (OPTIONAL) ###
enwrap {
force shape parameters $m -boundary_width 200u -channel_width 50u
query plan shape $m

# force plan blockage parameters $m -enable all -automatic on
# force plan halo -top 15u -bottom 15u -left 5u -right 5u $m $macro_cell
# force plan clearance $m -left 10u -bottom 5u -right 10u -top 5u $macro_cell

### Perform Floorplan Shaping ###
config prepare hyper on
force delay adaptive_buffering $m on -hierarchical on
run place cluster $m -shape -macro_style optimized -timing_effort medium

} rhy-shape $m

enwrap {
set no_of_mlayers [query layer routing $m ]
set higher_mlayer [lindex $no_of_mlayers [expr [llength $no_of_mlayers] -3 ] ]
set lower_mlayer [lindex $no_of_mlayers [expr [llength $no_of_mlayers] -4 ] ]
set m1_layer [lindex $no_of_mlayers 0 ]
#ring
force route power2 ring $m  top -ring {VSS {METAL6 12u 1.5u horizontal} {METAL5 12u 1.5u vertical}} -ring {VDD12 {METAL6 12u 16.5u horizontal} {METAL6 12u 16.5u vertical}}

run route power2 ring $m  -style separate -inner_shape -specs {top}

#mesh
force model routing layer $m highest $higher_mlayer
force route power2 mesh $m v7 -orientation vertical -wire ” VDD12 METAL6 4.0u 0.6u -extend both ” -wire ” VSS METAL6 4.0u 5.8u -extend both ”

run route power2 mesh $m -specs {v7} -inner_shape -group_spacing 30u -macro_clip_range 10u

force route power2 mesh $m h6 -orientation horizontal -wire ” VDD12 METAL5 4.0u 0.6u -extend both ” -wire ” VSS METAL5 4.0u 5.8u -extend both ”

run route power2 mesh $m -specs {h6} -inner_shape -group_spacing 30u -macro_clip_range 10u
#vias and rail
run route power2 rail $m -macro_clip_range 10u -extend_left -extend_right
force route power2 via $m mesh2rail -from {METAL1 rail} -to {METAL6 mesh} -stack {{VIA12 1 1} {VIA23 1 1} {VIA34 1 1} {VIA45 1 1} {VIA56
1 1}}
run route power2 via $m -specs_only -specs mesh2rail
run route power2 pin $m -start_bend 10u -tap_all_pin_layers -pin_type pg

# Connect signal pins that are driven by constant cells to the supply nets
run domain apply $m
run gate constant2power $m

} rhy-power $m

enwrap {
config flow $m set placement

if { $scan == “1″ } {
config scan optimize $m -hierarchy on
run scan optimize $m $l
}
### Buffer High Fanout Nets ###
run gate buffer wire $m $l -balance_hfn -min_hfn_size 30 -skip_lwb
run place clean $m
} rhy-rgbw1-rpc1 $m

enwrap {

### Configure the Global Router for coarse-grain level buckets, 1×1 buckets (OPTIONAL) ###

config route global channel_style $m -preference macro -minimize_channel_vias on
run route global $m -hierarchy -bw -largenet  -override_sign_in_check

} rhy-grx1 $m

enwrap {
config message level PO-100 info
config message level PO-113 info
run plan pushdown transit $m -mode pushdown_areas_only

run pin assign $m -pin_mode global

config route global channel_style $m -preference channel -minimize_channel_vias on
run route global $m -hierarchy -bw -override_sign_in_check

} rhy-grx3-nrpb $m

enwrap {
run plan partition commit $m
run prepare macro timing $m boundary
config limit optimize -type fanout strict
run gate buffer wire $m $l -balance_hfn -global -acc
run route global $m -point_pin -hierarchy -bw -override_sign_in_check

run optimize strength $m $l -iteration 3
run prepare macro timing $m full
run place clean $m

} rhy-grx4-commit $m

### Perform Clock Tree Synthesis (OPTIONAL) ###
config place detail -tolerate_hyper_cells

fix clock_hier $m $l

enwrap {
data pushdown power $m -boundary_cross always

} rhy-pushdown-power $m

### Push Down Scan Infrastructure (OPTIONAL) ###
#data loop x model_soft_macro $m {
#   report dft scan push_down $m -block $x -file [data get $x name].scan.rpt
#   }

### Push Down Blockages (OPTIONAL) ###
# data pushdown physical $m -placement_blockages

fix budget $m $l -setup_buffer

### Perform SMC Prototype Placement (OPTIONAL) ###
config check design type undriven_pins -severity warning
config check design type outside_corebox_wires -severity warning
config check design type undriven_nets -severity warning
config check design type wire_offgrid -severity warning

data loop cell model_soft_macro $m {
set model [data only cell_model $cell]
set bbox [query cell is_blackbox $cell]
if { $bbox == 0} {
puts “running fix cell on $model”
config route global channel_style $model -preference macro
fix cell $model $l -prototype -override_sign_in_check
} else {
puts “skipping fix cell on $model because it is a black box”
}
}

### Perform Top-level Prototype Placement (OPTIONAL) ###
config check design type shrunk_bbox_model -severity info
fix cell $m $l -prototype

### Hand-off to Talus Vortex for Block Implementation ###
# force model view
# export view

return
