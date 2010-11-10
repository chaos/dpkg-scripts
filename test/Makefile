TESTS=$(shell seq 1 83) $(shell seq 100 103)

all:

check: buildtests querytests

buildtests:
	./runtests $(TESTS)	

querytests:
	./runquerytests $(TESTS)	

querysrc:
	./runquerytests -s $(TESTS)

clean:
	rm -f *.deb *.out *.qtry *.diff
