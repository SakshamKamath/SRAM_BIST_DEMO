PYTHON ?= /usr/bin/python3.12
.PHONY: check lint sim synth
check:
	$(PYTHON) scripts/check.py all
lint:
	$(PYTHON) scripts/check.py lint
sim:
	$(PYTHON) scripts/check.py sim
synth:
	$(PYTHON) scripts/check.py synth
