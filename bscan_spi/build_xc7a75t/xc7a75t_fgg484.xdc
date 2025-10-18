# XC7A75T-FGG484 BSCAN SPI Constraints
# For target-board-3 with Spansion S25FL064 flash
#
# SPI Flash Pin Connections (from schematic):
# nCS:      T19 (SPI_CS0)
# SI_IO0:   P22 (SPI_IO0) - MOSI
# SO_IO1:   R22 (SPI_IO1) - MISO
# nWP_IO2:  P21 (SPI_IO2)
# nHOLD_IO3: R21 (SPI_IO3)

# SPI Chip Select (active low) - CSB_ext
set_property PACKAGE_PIN T19 [get_ports CSB_ext]
set_property IOSTANDARD LVCMOS33 [get_ports CSB_ext]

# SPI MOSI (Master Out Slave In) - MOSI_ext (IO0)
set_property PACKAGE_PIN P22 [get_ports MOSI_ext]
set_property IOSTANDARD LVCMOS33 [get_ports MOSI_ext]

# SPI MISO (Master In Slave Out) - MISO_ext (IO1)
set_property PACKAGE_PIN R22 [get_ports MISO_ext]
set_property IOSTANDARD LVCMOS33 [get_ports MISO_ext]

# SPI Write Protect - IO2 (tied high in VHDL)
set_property PACKAGE_PIN P21 [get_ports IO2]
set_property IOSTANDARD LVCMOS33 [get_ports IO2]

# SPI Hold - IO3 (tied high in VHDL)
set_property PACKAGE_PIN R21 [get_ports IO3]
set_property IOSTANDARD LVCMOS33 [get_ports IO3]

# LEDs for status indication (assigned to unused pins)
# These are debug outputs from the VHDL - GLED is steady ON, RLED flashes during SPI access
# Using generic unused I/O pins since board doesn't have dedicated LEDs exposed
set_property PACKAGE_PIN N15 [get_ports RLED]
set_property IOSTANDARD LVCMOS33 [get_ports RLED]
set_property PACKAGE_PIN B22 [get_ports GLED]
set_property IOSTANDARD LVCMOS33 [get_ports GLED]

# Configuration settings
# Note: These are removed because this bitstream is loaded via JTAG, not from SPI flash
# set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 1 [current_design]
# set_property CONFIG_MODE SPIx1 [current_design]
# set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

# Configuration bank voltage (required for 7-series)
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# Timing constraints (not critical for BSCAN SPI bridge)
# The JTAG clock drives everything, typically 1-10 MHz
