.DEFAULT_GOAL := help
.PHONY: help verify quick
help:
	@printf '%s\n' 'make verify  # publication integrity and file lists' 'make quick   # generated layout and host transport checks' 'See docs/reproduce.md for FPGA/model flows.'
verify:
	@python3 tools/release/verify_snapshot.py
quick:
	@M1_PYTHON=python3 ./scripts/m1 generate_layout --check
	@M1_PYTHON=python3 ./scripts/m1 generate_host_control --check
	@M1_PYTHON=python3 ./scripts/m1 board_transport_test --output build/transport-test
