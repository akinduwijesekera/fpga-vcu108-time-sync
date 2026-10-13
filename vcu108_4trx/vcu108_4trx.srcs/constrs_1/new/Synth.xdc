##
## Icon Constraints
##
  # unnecessary, clock created by MIG -> c0_sys_clk_p is name of new clock
#create_clock -period 3.333 -name sysclk [get_ports SysClk_clk_p]

##
## Gtrefclk lock constraints
##
set_property PACKAGE_PIN AK39 [get_ports mgtrefclk0_n_in]
set_property PACKAGE_PIN AK38 [get_ports mgtrefclk0_p_in]

##
## Refclk constraints
##
create_clock -period 1.538 -name gtrefclk0 [get_ports mgtrefclk0_p_in]

##
## System clock pin locs and timing constraints
##
set_property PACKAGE_PIN G31 [get_ports SysClk_clk_p]
set_property IOSTANDARD DIFF_SSTL12 [get_ports SysClk_clk_p]

##
## RESET Port
##
set_property PACKAGE_PIN E36 [get_ports CpuReset_in]
set_property IOSTANDARD LVCMOS12 [get_ports CpuReset_in]
