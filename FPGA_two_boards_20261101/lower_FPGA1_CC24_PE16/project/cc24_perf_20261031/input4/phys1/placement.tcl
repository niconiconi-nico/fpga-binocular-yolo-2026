cd [file dirname [info script]]
if {[catch {
import_db camera_yolo_gate.db
set_param place pr_strategy 2
set_param place effort high
set_param place hfn_opt_effort high
set_param place opt_timing high
set_param place logic_level_opt off
set_param place aggressive_opt 20
set_param place aggr_neighbor_dist 5
set_param place enhanced_beeline_opt 3
set_param place timing_driven_mode off
set_param place shifter_opt on
set_param place crit_path_opt off
set_param place post_place_opt high
set_param place split_data_from_clock on
set_param place preplace_floorplan off
commit_param -step place
puts [list TF_GP_ACTIVATION_GATE [get_param place timing_driven_mode]]
if {[get_param place timing_driven_mode] ne {off}} {error {Causal GP activation switch absent}}
report_param -stage place -detail -all -file own_parameters.rpt
place
export_db own_place_raw.db
update_timing -mode manhattan
export_db own_place_pre_reports.db
report_timing_summary -file own_place.timing
report_area -io_info -file own_place.area
export_db own_place.db
puts "OWN_FIRST_PLACE_FINISHED"
} e]} {puts stderr $e;puts stderr $::errorInfo;exit 2}
exit 0
