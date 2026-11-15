# Optional: gtkwave sim/tb_systolic_array_3x3.vcd docs/waveforms/tensorax_array.gtkw --script=docs/waveforms/tensorax_markers.tcl
# Times are for Test 1 (README ramp case) of tb_systolic_array_3x3.v
gtkwave::setZoomRangeTimes 0 130000
gtkwave::setNamedMarker A 35000 "cycle 1: first feed edge"
gtkwave::setNamedMarker B 55000 "cycle 3: C00 final"
gtkwave::setNamedMarker C 95000 "cycle 7: all C final"
gtkwave::setMarker 95000
