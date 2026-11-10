cd [file dirname [info script]]
if {[catch {
import_device ph1_35p.db -package PH1P35MDG324 -speed 3
import_db {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/route1/final.db}
clear_sdc
read_sdc {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/physical_signoff1.sdc}
update_timing -mode final
export_db bitgen_input.db
bitgen -bit FPGA2_CLAUDE_ZOOM_ENGINEERING.bit
puts {CLAUDE_ZOOM_BITGEN_DONE}
} e]} {puts stderr $e;puts stderr $::errorInfo;exit 2}
exit 0
