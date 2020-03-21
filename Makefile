.PHONY : test

EMACS ?= emacs
LOADPATH = -L .

test:
	emacs -Q -batch $(LOADPATH) \
		-l test/private-functions.el \
		-f ert-run-tests-batch-and-exit
