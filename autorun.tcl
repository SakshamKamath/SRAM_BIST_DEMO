cd yosys;
oseda -2026.02 yosys -c scripts/yosys_synthesis.tcl;
cd ..;
# #TOCHECK - is keep hierarchy needed in yosys read_slang - check in terms of area


##### Open STA #####

# cd ../sta;
# oseda -2026.02 sta scripts/opensta.tcl;


##### OpenRoad #####
cd openroad;
rm -rf save;
oseda -2026.04 openroad scripts/01_floorplan.tcl;
oseda -2026.04 openroad scripts/02_placement.tcl;
oseda -2026.04 openroad scripts/03_cts.tcl;
