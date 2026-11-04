# Simulation of the Pocket-specific modules (Icarus Verilog, nvc for the VIC)
CORE = ../src/fpga/core
V20  = ../src/fpga/VIC20_MiSTer/rtl

all: gcr media vic hid autostart osk

# VIC20_MiSTer's M6561 blanking: the window sizes in vic20_video.sv and video.json
VIC_WANT = frame 228-228 x 283 frame 204-204 x 244
vic:
	cd vic && for n in 0 1; do nvc -a ../$(V20)/m6561.vhd tb_vic.vhd -e tb_vic -gNTSC=$$n -r 2>&1 | grep -o 'frame.*'; done > geometry.txt
	@if [ "`tr '\n' ' ' < vic/geometry.txt`" = "$(VIC_WANT) " ]; then echo "vic: PAL 228x283, NTSC 204x244 OK"; \
	else echo "vic: FAIL, got"; cat vic/geometry.txt; exit 1; fi

# gcr_synth byte-exact against Main_MiSTer's D64 -> GCR; gcr_decode at any bit rotation
gcr:
	python3 run_gcr.py

# vic20_media + ddram_psram: PRG streaming, D64 / G64 / D81 mount and write-back
media:
	python3 run_media.py

# hid_c64: make/break events and mouse reports
hid:
	iverilog -g2012 -o hid_tb.vvp hid_tb.sv $(CORE)/hid_c64.sv
	vvp -n hid_tb.vvp | grep -v finish
	rm -f hid_tb.vvp

# autostart: LOAD/RUN typed at the prompt only
autostart:
	iverilog -g2012 -o autostart_tb.vvp autostart_tb.sv $(CORE)/autostart.sv
	vvp -n autostart_tb.vvp | grep -v finish
	rm -f autostart_tb.vvp

# on-screen keyboard and loading screen rendered to sim/video/*.png (docs/osk.png)
osk:
	mkdir -p video
	iverilog -g2012 -I$(CORE) -o osk_tb.vvp osk_tb.sv $(CORE)/osk.sv
	vvp -n osk_tb.vvp | { grep -v finish || true; }   # prints nothing but $$finish when all is well
	rm -f osk_tb.vvp
	python3 ppm2png.py video/osk_frame.ppm video/osk_frame.png
	python3 ppm2png.py video/load_frame.ppm video/load_frame.png

clean:
	rm -rf gcr media video vic/work __pycache__

.PHONY: all gcr media vic hid autostart osk clean
