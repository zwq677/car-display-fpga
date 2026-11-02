puts "PROBE_START"
if {[catch {read_device_id} e]} {
    puts "PROBE_ERR: $e"
}
puts "PROBE_END"
exit
