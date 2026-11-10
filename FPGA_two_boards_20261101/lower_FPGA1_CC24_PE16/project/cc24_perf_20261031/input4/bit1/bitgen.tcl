cd [file dirname [info script]]
if {[catch {
import_db own_final.db
commit_param -step bitgen
set_param bitgen compress on
bitgen -bit CC24_PE16_ACCEL_20261031.bit
export_bitgen_param -file candidate.bitgen_param.f
puts {CC24_ACCEL_BITGEN_FINISHED}
} e]} {puts stderr $e;puts stderr $::errorInfo;exit 2}
exit 0
