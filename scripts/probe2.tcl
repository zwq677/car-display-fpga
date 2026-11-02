puts "PROBE_START"
if {[catch {list_devices} e]} { puts "LIST_ERR: $e" }
if {[catch {read_device_id} e2} { puts "RNID_ERR: $e2" }
puts "PROBE_END"
exit
