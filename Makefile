MAKEFILE_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

RUN_TAG = $(shell ls librelane/runs/ | tail -n 1)
TOP = chip_top

PDK_ROOT ?= $(MAKEFILE_DIR)/gf180mcu
PDK ?= gf180mcuD
PDK_TAG ?= 1.1.2

.DEFAULT_GOAL := help

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'
.PHONY: help

all: librelane ## Build the project (runs LibreLane)
.PHONY: all

clone-pdk: ## Clone the GF180MCU PDK repository
	rm -rf $(MAKEFILE_DIR)/gf180mcu
	git clone https://github.com/wafer-space/gf180mcu.git $(MAKEFILE_DIR)/gf180mcu --depth 1 --branch ${PDK_TAG}
.PHONY: clone-pdk

librelane: ## Run LibreLane flow (synthesis, PnR, verification)
	librelane librelane/config.yaml --pdk ${PDK} --pdk-root ${PDK_ROOT} --manual-pdk
.PHONY: librelane

librelane-yolo: ## Run full flow, including DRC, but don't quit after DRC errors
	librelane librelane/config.yaml --pdk ${PDK} --pdk-root ${PDK_ROOT} --manual-pdk --skip Checker.MagicDRC --skip Checker.KLayoutDRC
.PHONY: librelane-yolo

librelane-nodrc: ## Run LibreLane flow without DRC checks
	librelane librelane/config.yaml --pdk ${PDK} --pdk-root ${PDK_ROOT} --manual-pdk --skip KLayout.DRC --skip Magic.DRC
.PHONY: librelane-nodrc

librelane-klayoutdrc: ## Run LibreLane flow without magic DRC checks
	librelane librelane/config.yaml --pdk ${PDK} --pdk-root ${PDK_ROOT} --manual-pdk --skip Magic.DRC
.PHONY: librelane-klayoutdrc

librelane-magicdrc: ## Run LibreLane flow without KLayout DRC checks
	librelane librelane/config.yaml --pdk ${PDK} --pdk-root ${PDK_ROOT} --manual-pdk --skip KLayout.DRC
.PHONY: librelane-magicdrc

librelane-openroad: ## Open the last run in OpenROAD
	librelane librelane/config.yaml --pdk ${PDK} --pdk-root ${PDK_ROOT} --manual-pdk --last-run --flow OpenInOpenROAD
.PHONY: librelane-openroad

librelane-explore: ## Run synthesis exploration
	librelane librelane/config.yaml --pdk ${PDK} --pdk-root ${PDK_ROOT} --manual-pdk --last-run --flow SynthesisExploration
.PHONY: librelane-explore

librelane-klayout: ## Open the last run in KLayout
	librelane librelane/config.yaml --pdk ${PDK} --pdk-root ${PDK_ROOT} --manual-pdk --last-run --flow OpenInKLayout
.PHONY: librelane-klayout

sim: ## Run RTL simulation with cocotb
	cd cocotb; PDK_ROOT=${PDK_ROOT} PDK=${PDK} python3 chip_top_tb.py
.PHONY: sim

sim-gl: ## Run gate-level simulation with cocotb (after copy-final)
	cd cocotb; GL=1 PDK_ROOT=${PDK_ROOT} PDK=${PDK} python3 chip_top_tb.py
.PHONY: sim-gl

sim-view: ## View simulation waveforms in GTKWave
	gtkwave cocotb/sim_build/chip_top.fst
.PHONY: sim-view

regblocks: ## Regenerate all register blocks and their headers
	./fpgascripts/regblock -a hdl/apu/ipc/apu_ipc_regs.yml
	./fpgascripts/regblock -a hdl/apu/aout/apu_aout_regs.yml
	./fpgascripts/regblock -a hdl/apu/timer/apu_timer_regs.yml
	./fpgascripts/regblock -a hdl/spi_stream/spi_stream_regs.yml
	./fpgascripts/regblock -a hdl/gpio/gpio_regs.yml
	./fpgascripts/regblock -a hdl/padctrl/padctrl_regs.yml
	./fpgascripts/regblock -a hdl/dispctrl/regs/ppu_dispctrl_rb180_regs.yml
	./fpgascripts/regblock -a hdl/riscboy/hdl/graphics/ppu/regs/ppu_regs.yml
	./fpgascripts/regblock -a hdl/riscboy/hdl/peris/pwm_tiny/pwm_tiny_regs.yml
	./fpgascripts/regblock -a hdl/vuart/vuart_dev_regs.yml
	./fpgascripts/regblock -a hdl/vuart/vuart_host_regs.yml
	./fpgascripts/regblock -a hdl/uart/uart_regs.yml
	./fpgascripts/regblock -a hdl/clocks/clocks_regs.yml
	./fpgascripts/regblock -a hdl/syscfg/syscfg_regs.yml
.PHONY: sim-view

copy-final: ## Copy final output files from the last run
	rm -rf final/
	cp -r librelane/runs/${RUN_TAG}/final/ final/
.PHONY: copy-final

render-image: ## Render an image from the final layout (after copy-final)
	mkdir -p img/
	PDK_ROOT=${PDK_ROOT} PDK=${PDK} python3 scripts/lay2img.py final/gds/${TOP}.gds img/${TOP}.png --width 4096 --oversampling 4
.PHONY: copy-final
