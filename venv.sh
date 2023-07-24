#!/bin/sh

if [ -z "$SHELL" ]; then
	SHELL=/bin/sh
fi

if [ ! -d _venv ]; then
	python3 -m venv _venv
	. _venv/bin/activate
	pip install -r ./requirements.txt
	exec $SHELL
else
	. _venv/bin/activate
	exec $SHELL
fi
