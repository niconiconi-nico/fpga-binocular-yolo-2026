cd [file dirname [info script]]
if {[catch {
import_db own_place.db
set_param route effort high
set_param route multi_try_route_bad_qor_check off
set_param route post_route_opt high
commit_param -step route
route
export_db own_route_raw.db
fix_hold
export_db own_hold_fixed.db
update_timing -mode final
export_db own_final_pre_reports.db
export_db own_final.db
write_verilog own_routed.v
report_qor -step route -file own_route.qor
report_timing_status -file own_phy.ts
report_timing_summary -file own_pr.timing
report_area -io_info -file own_final.area
flow_status -file own.status
puts {OWN_DRC_BEGIN}
drc_check -all -verbose
puts {OWN_DRC_END}
report_route_status -file own_route_status.txt
report_timing_exception -file own_exceptions.rpt
report_timing_ignored -file own_ignored.rpt
puts {OWN_FIRST_ROUTE_FINISHED_NOT_QUALIFIED}
} e]} {puts stderr $e;puts stderr $::errorInfo;exit 2}
exit 0
