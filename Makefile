SVNURL	= https://eris.llnl.gov/svn/lclocal/public/$(NAME)
NAME	:= $(shell awk '/[Nn]ame:/    {print $$2}' META)
VERSION := $(shell awk '/[Vv]ersion:/ {print $$2}' META)
RELEASE	:= $(shell awk '/[Rr]elease:/ {print $$2}' META)
BUILDURL:= https://eris.llnl.gov/svn/buildfarm/trunk/build
TRUNKURL:= $(SVNURL)/trunk
TAGURL	:= $(SVNURL)/tags/$(VERSION)

CFLAGS	= -Wall -g -DWITH_LSD_FATAL_ERROR_FUNC -DWITH_LSD_NOMEM_ERROR_FUNC

all: dpkg-tmplocal dpkg-lndir dpkg-verify base64 md5sum

dpkg-verify: dpkg-verify.o md5sum.o base64.o list.o  hash.o
	$(CC) -o $@ dpkg-verify.o md5sum.o base64.o list.o hash.o -lssl

md5sum: md5sum.c
	$(CC) -Wall -DSTAND -o $@ md5sum.c -lssl
base64: base64.c
	$(CC) -Wall -DSTAND -o $@ base64.c -lssl

check:
	make -C test check

clean:
	rm -f dpkg-tmplocal dpkg-lndir dpkg-verify md5sum base64
	rm -f *.o
	rm -f *.rpm *.bz2
	make -C test clean

veryclean: clean
	rm -f build 

install: install_rpms

rpms-working: clean build
	./build --nomock --snapshot . 
rpms-trunk: build
	./build --nomock --snapshot $(TRUNKURL)
rpms-release: build
	./build --nomock --project-release=$(RELEASE) $(TAGURL)
build:
	svn cat $(BUILDURL) >$@
	chmod +x $@

diff:
	svn diff .
commit:
	svn commit .
tagrel:
	svn copy -m "tag" $(TRUNKURL) $(TAGURL)

# development only!
doit:
	rm -f *.rpm *.bz2
	build .
	sudo rpm -Uvh *.x86_64.rpm
