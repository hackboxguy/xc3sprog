# Vivado TCL Script to build BSCAN SPI bitstream for XC7A75T-FGG484
# For target-board-3 with Spansion S25FL064 flash
#
# Usage: vivado -mode batch -source build_xc7a75t_fgg484.tcl
#

# Set the device
set part "xc7a75tfgg484-2"
set project_name "bscan_xc7a75t_fgg484"
set output_dir "build_xc7a75t"

# Create project directory
file mkdir $output_dir
cd $output_dir

# Create project
create_project $project_name . -part $part -force

# Add VHDL source file
add_files ../bscan_xc7_spi.vhd
set_property FILE_TYPE {VHDL} [get_files ../bscan_xc7_spi.vhd]

# Add constraint file
add_files -fileset constrs_1 ../xc7a75t_fgg484.xdc

# Set top module
set_property top top [current_fileset]

# Synthesis settings
set_property strategy {Flow_PerfOptimized_high} [get_runs synth_1]

# Implementation settings
set_property strategy {Performance_ExplorePostRoutePhysOpt} [get_runs impl_1]

# Run synthesis
puts "Running synthesis..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Check synthesis
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis failed!"
    exit 1
}
puts "Synthesis completed successfully"

# Run implementation
puts "Running implementation..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# Check implementation
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Implementation failed!"
    exit 1
}
puts "Implementation completed successfully"

# Copy bitstream to parent directory with descriptive name
puts "Copying bitstream..."
file copy -force \
    ${project_name}.runs/impl_1/top.bit \
    ../xc7a75t-2fgg484.bit

puts ""
puts "================================================================"
puts "BSCAN SPI bitstream build completed successfully!"
puts "Output file: bscan_spi/xc7a75t-2fgg484.bit"
puts ""
puts "Deploy to Pi4:"
puts "  scp bscan_spi/xc7a75t-2fgg484.bit \\"
puts "      pi@pi4-flasher-008:~/micropanel/fpga/share/xc3sprog/bscan_spi/"
puts ""
puts "Test with:"
puts "  sudo xc3sprog -c gpiod_creator -p 0 \\"
puts "    -I.../xc7a75t-2fgg484.bit -v"
puts "================================================================"
puts ""

# Close project
close_project
cd ..

exit 0
