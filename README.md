# Introduction

This page describes how to use the dpkg-scripts packaging system.

_Note that dpkg-scripts is no longer in use.  This repo is not maintained
and exists for historical purposes only._

## Motivation

Although packaging /usr/local introduces additional process for software
maintainers, it has significant benefits, including:

- Ability for users and staff to query package ownership for a file, and the
  set of all files comprising a package.  Before packaging, files could be
  installed, their intended purpose forgotten, then they might persist
  indefinitely.
- Ability for users and staff to query the list of installed packages and
  versions.  Before packaging, determining what was installed involved looking
  around in many  different directories, some quite obscure since there was
  little regularity in the file system.
- Updates across multiple instances of /usr/local are less labor intensive,
  less error prone, less prone to "drift", and automatable.  Before packaging,
  updating  /usr/local was for the most part a manual process, subject to
  errors and inconsistancies.
- It becomes feasible to have one /usr/local per cluster, which makes phased
  rollouts possible, starting with QA clusters and ending with largest/most
  critical production clusters.  Before packaging, new software was "tested"
  by installing it the /usr/local shared by all machines with a common
  architecture.
- It is impossible for an errant install to clobber files belonging to a
  working package.  Before packaging, cases were reported of users removing
  large sections of /usr/local that had to be restored from backup.
- Modes and ownerships of files and directories can be made more uniform and
  secure.  Before packaging, directories had their mode and ownership set so
  that groups of LC staff could make updates without root capability.  As a
  result, ownership of files was often set to the user who installed it.
- With uniform root:root ownership of files and directories, packagers will
  not build tests that work for the package owner but not the users due to
  erroneously restrictive permissions.  Before packaging, the combination of
  a restrictive default umask and file ownership set to the installer would
  frequently result in packages that work for the installer but not for others.
- Tests can be integrated with each package and run at any time by any user.
  Before packaging, testing was mostly ad-hoc, and not accessible outside of
  a small group. Many packages, especially those not configured as the current
  defaults, would get no testing.  Given that packages were rarely de-installed
  because usage was unknown, old packages could quietly become dysfunctional.
- Package environment information does not need to be seperately maintained in
  dotkits and script wrappers.  Manually duplicating information makes it
  prone to inconsistancy.
- Organizing documentation as package metadata and summarizing system-wide
  becomes possible.  Before packaging, documentation had to be collected
  manually and was not updated as packages were updated.
- The packaging system encourages uniform directory structure.  Before
  packaging, each software maintainer more or less chose their own strategy
  for organizing their products.  Although each strategy may have been
  self-consistent, the overall result was very inconsistent and difficult to
  navigate.
- Package sources and configuration are captured in a source code repository
  and therefore are readily accessible among LC personnel.  Before packaging,
  the steps needed to install a package were private to the individual,
  perhaps undocumented even privately, and were not easily transferred or
  reviewed.
- A uniform strategy for wrappers allows logging of package and dotkit usage,
  so it can be determined which users are using which versions of software.
  Before packaging, several software maintainers developed different logging
  strategies, some of which were insecure.
- A packaging utility leverages private namespaces to give packagers the
  ability to create private sandbox /usr/local instances on production machines
  where they can test software. Before packaging, sometimes the first place
  software would be tried out would be on a live file system.
- Packaging decouples package installation from package implementation.  That
  is, an expert in a particular software area can create a package and someone
  else can roll it out.  Before packaging, experts had to be called upon to
  roll out updates.
- Packaging makes the environment transportable, e.g. to a vendor site during
  integration of a new cluster.  Before packaging, transporting the environment
  meant laboriously following symlinks all over the place to capture all the
  needed pieces, or copying the entire contents of /usr/local and other
  directories.

## Leveraging Debian Packaging for /usr/local

Dpkg is the installer and package format used by Debian Linux.  It has an
extensible metadata format that was leveraged heavily in our implementation of
packaging for /usr/local.  It was converted for /usr/local use with minimal
effort, due to the fact that it has been used in similar efforts, for example
the
[Fink Project](http://finkproject.org/) for packaging open source software for
MacOS.  The dpkg program itself is packaged in the dpkg RPM for CHAOS.

A new source packaging format based on subversion was developed specifically
for Livermore.  It is implemented in the dpkg-scripts RPM for CHAOS and is
described in detail below.

In addition, since the environment becomes rather complicated for side
installed packages, and since dotkit is the defacto standard environment
packaging tool used at Livermore, dotkit was integrated with dpkg-scripts.
A stripped down version of dotkit was packaged for back-end use by dpkg-scripts
in the dpkg-dotkit RPM for CHAOS.

## System Administration

### Initializing an Empty /usr/local

Verify that you have the necessary RPM's installed:
```console
$ rpm -q dpkg dpkg-scripts dpkg-dotkit apt apt-utils
dpkg-1.13.25-8.ch4
dpkg-scripts-1.38-1.ch4
dpkg-dotkit-060613-1.ch4
apt-0.7.9-5chaos.ch4
apt-utils-0.7.9-5chaos.ch4
```
Mount /usr/local read-write and run:
```console
$ sudo dpkg-initialize
```
Note: /usr/local should only be mounted read-write on one node.  Other nodes
should mount /usr/local read-only, but they should still have the three dpkg
RPM's installed to support wrappers, dpkg queries, etc..

### Populating an empty /usr/local with current packages

```console
$ sudo apt-get update
$ sudo apt-get install lclocal
$ sudo /usr/local/bin/lclocal -U
```

### Using the dpkg Command

#### Operations on Installed Packages

To list installed packages:
```console
$ dpkg -l
Desired=Unknown/Install/Remove/Purge/Hold
| Status=Not/Installed/Config-files/Unpacked/Failed-config/Half-installed
|/ Err?=(none)/Hold/Reinst-required/X=both-problems (Status,Err: uppercase=bad)
||/ Name                     Version    Description
+++-========================-==========-======================================
ii  icc-10.0.025             5          Intel C++ Compiler
ii  ifort-10.0.025           4          Intel Fortran Compiler
ii  license                  1.ocf      License configuration for LLNL OCF net
```
To install/upgrade a package:
```console
$ sudo dpkg -i ifort-10.0.025_4_linux-amd64.deb
(Reading database ... 6061 files and directories currently installed.)
Preparing to replace ifort-10.0.025 4 (using ifort-10.0.025_4_linux-amd64.deb) ...
Unpacking replacement ifort-10.0.025 ...
Setting up ifort-10.0.025 (4) ...
```
To remove a package:
```console
$ sudo dpkg -r ifort-10.0.025
(Reading database ... 6061 files and directories currently installed.)
Removing ifort-10.0.025 ...
```
To list files belonging to a package:
```console
$ dpkg -L license
/usr/local/etc
/usr/local/etc/license.client
/usr/local/etc/license.client.intel
```
To find which package a file belongs to:
```console
$ dpkg -S /usr/local/etc/license.client
license: /usr/local/etc/license.client
```

#### Operations on Uninstalled deb files

To list files belonging to a package:
```console
$ dpkg -c license_1.ocf_all.deb
drwxr-xr-x garlick/garlick   0 2007-10-25 14:46:35 ./usr/local/etc/
-rwxr-xr-x garlick/garlick 152 2007-10-25 14:46:35 ./usr/local/etc/license.client
-rwxr-xr-x garlick/garlick  58 2007-10-25 14:46:35 ./usr/local/etc/license.client.intel
```
To list information about a package:
```console
$ dpkg -I license_1.ocf_all.deb
 new debian package, version 2.0.
 size 1168 bytes: control archive= 732 bytes.
     130 bytes,     3 lines      buildinfo
     387 bytes,    14 lines      buildlog
     172 bytes,     7 lines      control
     216 bytes,     5 lines      dk
     132 bytes,     2 lines      md5sums
 Package: license
 Version: 1.ocf
 Architecture: all
 Maintainer: Jim Garlick <garlick@llnl.gov>
 Description: License configuration for LLNL OCF network
 Depends:
 Section: root
```
#### Viewing Dpkg Logs

To view the dpkg log:
```console
$ tail -100 /usr/local/dpkg-db/dpkg.log
...
```
To view the dpkg dotkit/wrapper log, presuming the local7.info syslog channel
is being logged to /var/log/messages:
```console
$ egrep "dpkg-wrapper|dpkg-dotkit" /var/log/messages
...
```

### Using the Alternatives System (Deprecated)

The alternatives system is no longer used.  In dpkg-scripts-1.36, it is
replaced with default packages, described below.

### Working with Default Packages

Default packages are used to select a default among several side installed
versions of a package.  A default package contains only symlinks and wrappers--
it has no true content of its own.  Its package name and version is derived
from the package it points to:  a default package that points to a package
named "pkg-v" with version "r", would be named "pkg" with version
"default-v-r".  To change the current default, simply install the version of
the default package that you want.

## Building Packages

### Package Names

Package names (i.e. as specified by the PKG_NAME in package.conf) must
consist only of lower case letters (a-z), digits (0-9), plus (+) and minus (-)
signs, and periods (.). They must be at least two characters long and must
start with an alphanumeric character.

http://www.debian.org/doc/debian-policy/ch-controlfields.html#s-f-Package

### Creating a Simple Package

The dpkg-mkdeb(8) utility is used to turn package source materials into a deb
file.  The minimum requirements for a package is a package.conf file, really
just a bash script that is sourced by dpkg-mkdeb.  For example:
```sh
PKG_NAME=hello-pkg
PKG_VERSION=1
PKG_SECTION=tools
PKG_SHORT_DESCRIPTION="A simple hello world package"
PKG_ARCH=all
PKG_MAINTAINER="Your Name Here <you@llnl.gov>"
PKG_DK_CATEGORY=testing/ephemeral
PKG_DK_HELP="This package has no real content - it is for demonstration\n\
purposes only."

pkg_build()
{
    return 0
}

pkg_install()
{
    mkdir -p $1${bindir}

    # install an executable
    cat > $1${bindir}/hello <<EOT
#!/usr/bin/env bash
echo "hello world!"
EOT
    chmod +x $1${bindir}/hello

    return 0
}
```

You can put this file in a working directory and build a package as follows:
```console
$ dpkg-mkdeb .
dpkg-mkdeb: copying 'hello-pkg' source to tmpsrc
dpkg-mkdeb: building 'hello-pkg' in tmpsrc
dpkg-mkdeb: installing 'hello-pkg' to tmproot
dpkg-deb: building package `hello-pkg' in `hello-pkg_1.snapshot.20071119131115_all.deb'.
```
This produces a deb with the following contents:
```console
$ dpkg -c hello-pkg_1.snapshot.20071119131115_all.deb
drwxr-xr-x garlick/garlick   0 2007-11-19 13:11:15 ./usr/local/tools/
drwxr-xr-x garlick/garlick   0 2007-11-19 13:11:15 ./usr/local/tools/hello-pkg/
drwxr-xr-x garlick/garlick   0 2007-11-19 13:11:15 ./usr/local/tools/hello-pkg/bin/
-rwxr-xr-x garlick/garlick  40 2007-11-19 13:11:15 ./usr/local/tools/hello-pkg/bin/hello
```
### Testing Your Package

It is possible to test this package in a private sandbox of /usr/local as
follows (your sandbox is cleaned up when you exit the shell spawned by
dpkg-tmplocal):
```console
$ dpkg-tmplocal /bin/bash
$ apt-userinst -l hello-pkg_1.snapshot.20071119131115_all.deb
apt-userinst: Attempting to initialize empty /usr/local
apt-userinst: Importing Builder GPG key
apt-userinst: Running apt-get update..
apt-userinst: Attempting to install: hello-pkg_1.snapshot.20080130094609_all.deb
apt-userinst: Running apt-get -f -y install...
apt-userinst: Done.
$ dpkg -l
| Status=Not/Installed/Config-files/Unpacked/Failed-config/Half-installed
|/ Err?=(none)/Hold/Reinst-required/X=both-problems (Status,Err: uppercase=bad)
||/ Name                     Version    Description
+++-========================-==========-======================================
ii  hello-pkg                1.snapshot A simple hello world package

$ use -l hello-pkg

***** hello-pkg *****
  Test package for dpkg scripts
  This package has no real content - it is used
  to test the dpkg-mkdeb script

$ use hello-pkg
Prepending: hello-pkg (ok)
$ which hello
/usr/local/tools/hello-pkg/bin/hello
$ hello
hello world!
$ exit
```

apt-userinst is a script which initializes an empty /usr/local (if necessary)
installs a local .deb (with dpkg) then resolves any missing dependencies using
apt-get -f. See the section below on creating a test /usr/local for more
information.

### Storing Package Source Materials in Subversion

When you have a working package (or even sooner!), you should put it in
subversion.  First create a repo:
```console
$ TOP=https://svnpath/hello-pkg
$ svn mkdir -m initial-import $TOP $TOP/trunk $TOP/branches $TOP/tags
Committed revision 543.
```
If your package will be "side installed", that is if you want to support
multiple instances of your package installed simultaneously, you could create
a branch for each version that you will maintain:
```console
$ svn mkdir -m initial-import $TOP/branches/hello-pkg-1.0
Committed revision 544.
```
and do your work on each branch.  Otherwise, do your development in trunk.
Assuming you are developing in the branch created above, change to your working
directory and clean away any build products or other junk and import your work:
```console
$ cd hello-pkg
$ svn import -m initial-import $TOP/branches/hello-pkg-1.0
Adding         package.conf
Committed revision 545.
```
Now get rid of your original copy and check out a working copy from the
repository
```console
$ cd ..
$ mv hello-pkg hello-pkg.deleteme
$ svn co $TOP/branches/hello-pkg-1.0 hello-pkg-1.0
A    hello-pkg-1.0/package.conf
Checked out revision 545.
cd hello-pkg-1.0
```
If you are ready to produce a non-snapshot deb, first ensure that PKG_VERSION
in your package.conf is correct.  Since we have chosen to make this a
side-installed package, we embed the version (1.0) in
PACKAGE_NAME=hello-pkg-1.0 and set PKG_VERSION to 1.  To commit these
changes
```console
$ svn commit .
```
To create a tag:
```console
$ svn copy -m tag $TOP/branches/hello-pkg-1.0 $TOP/tags/hello-pkg-1.0_1
Committed revision 546.
```
Now you can build a deb from the tag:
```console
$ dpkg-mkdeb $TOP/tags/hello-pkg-1.0_1
dpkg-mkdeb: exporting 'hello-pkg-1.0' to tmpsrc
dpkg-mkdeb: building 'hello-pkg-1.0' in tmpsrc
dpkg-mkdeb: installing 'hello-pkg-1.0' to tmproot
dpkg-deb: building package `hello-pkg-1.0' in `hello-pkg-1.0_1_all.deb'.
```
Debs that are ready for production should be pushed into the APT repository.

### Packaging GNU Software

The pkg_build() and pkg_install() functions where somewhat contrived in
the last example.  With    GNU software, the pkg_build() function configures
and builds the software, and pkg_install() installs it.  For example,
valgrind's package.conf:
```sh
PKG_NAME=valgrind-3.2.3
PKG_VERSION=1
PKG_SECTION=tools
PKG_SHORT_DESCRIPTION="the valgrind debugging and profiling suite"
PKG_MAINTAINER="Jim Garlick <garlick@llnl.gov>"
PKG_DK_CATEGORY="performance/profile"
PKG_DK_HELP="\
Loads Valgrind and associated manpages\n\
  Commands: valgrind\n\
  Modifies: \$PATH, \$MANPATH\n\
For usage, see man pages."
PKG_doc="Valgrind doc index: ${prefix}/share/doc/valgrind/html/index.html"

pkg_build()
{
    tar -xjf valgrind-3.2.3.tar.bz2
    pushd valgrind-3.2.3
        ./configure --prefix=${prefix} --enable-only64bit
        make
    popd
}

pkg_install()
{
    mkdir -p $1${prefix}

    pushd valgrind-3.2.3
        make install DESTDIR=$1
    popd
}
```
The dpkg-mkdeb utility makes a copy of the directory/repo containing the
package source materials and chdirs there before executing the package.conf
functions.

Valgrind includes a tarball in its package source materials.  The first job
of the pkg_build() function is to unpack the tarball and chdir to the
untarred source tree.  It then runs configure and make.  The `${prefix}`
environment variable is set by dpkg-mkdeb to be the root of the package after
installation, derived from the PKG_SECTION and PKG_NAME settings, in this
case /usr/local/tools/valgrind-3.2.3.  If an error occurs in any part of
pkg_build(), dpkg-mkdeb will catch this and abort since it runs with
bash "-e" mode on.

The pkg_install() function takes a temporary install root directory as its
first argument.  This will be an empty directory in /tmp that you must populate
with a skeletal /usr/local containing your package's install materials.  GNU
autoconf-generated Makefiles are for the most part forgiving when it comes to
non-existant installation directories but it's good practice to create the
package prefix and let the Makefile do the rest.  Next step is to change
directory into the untarred (and now built) source tree and install to the
temporary root.  The DESTDIR Makefile variable is fairly standard for GNU
software.

If the two scripts run successfully, the contents of the installation root
will be bundled into a deb.

## Advanced Packaging Topics

### Packaged Dotkits

Packages may include dotkits as part of package metadata (DK_NODE must
include /usr/local/dpkg-db/info for these dotkits to be used).  A dotkit is
generated unless PKG_FLAGS includes the "nodk" flag.  An example dotkit
generated for the Intel icc compiler follows:
```sh
#c compilers/intel
#d Intel C++ Compiler
#h Loads Intel C++ compilers and associated man pages
#h  Commands: icc, icpc
#h  Modifies: $PATH, $MANPATH
#h For usage, see man pages or manuals in /usr/local/tools/icc-10.1.011/doc
dk_op -q license
dk_alter PATH /usr/local/tools/icc-10.1.011/bin
dk_alter MANPATH /usr/local/tools/icc-10.1.011/man
dpkg-logger -p icc-10.1.011 -d pid=$$ op=$_dk_op
```
Content is generated according to the following rules:
- PKG_DK_CATEGORY sets the value for #c.  If undefined, local-$PKG_SECTION
  is used.
- PKG_DK_HELP sets the content for #h.  If undefined, #h is omitted.
- If PKG_DEPENDS lists dependent packages and PKG_FLAGS does not include
  "decoupledk", the dotkit loads the dotkits for each dependent package with a
  dk\_op -q call.
- If the package has a bin directory, PATH is altered.
- If the package has a man directory, MANPATH is altered.
- If the package has an info directory, INFOPATH is altered.
- If the package has a lib directory containing shared objects,
  LD_LIBRARY_PATH is altered, unless PKG_FLAGS includes "noldpath".
 * Finally, dpkg-logger logs each time the package is loaded and unloaded.

If PKG\_dk is set, its content completely overrides the auto-generated dotkit.
Content may include macros (e.g. `$prefix`) and special characters such as `\n`
and they will be expanded in the dotkit.

Dotkits are leveraged by wrappers (see below), and by package.test scripts.

### Side Installed Packages

Some packages can be built with a prefix of /usr/local, but most should use
a prefix that is private to the package such as /usr/local/tools/pkgname.
The prefix is selected with the PKG_SECTION variable in package.conf.
Valid PKG_SECTION values are "root" (prefix=/usr/local), "tools"
(prefix=/usr/local/tools/pkgname), and "opt" (prefix=/usr/local/opt/pkgname).

For multiple versions of a package to be installed simultaneously, they must
have unique package names.  By convention, if a package will ever have multiple
versions installed, we append a hyphen followed by the vendor's version number
in the package name.  For example, two versions of the Intel icc compiler
package have PKG_NAME set to "icc-10.0.025" and "icc-10.1.011".  The
PKG_VERSION is then just a monotonically increasaing integer used to
distinguish local modifications or packaging changes.

### Wrappers

Some packages include wrapped executables in /usr/local/bin so users can run
them without altering their PATH or loading a dotkit.  For example, the Intel
compiler located in /usr/local/tools/icc-10.0.025/bin/icc has a wrapper named
/usr/local/bin/icc-10.0.025.  The packaging system can generate these wrappers
for you automatically.  List the executables you want wrapped in PKG_WRAPPERS
(comma or space separated). When the package is built, wrappers will be
included, named same as the executable with a hyphen and the package version
appended if the package name includes a version.  The wrapper simply calls:
```
#!/bin/bash
exec /usr/bin/dpkg-wrap pkgname execname "$@"
```
which loads the package's dotkit, runs the executable with the user's
arguments, and appends a log entry to syslog.

### Default Packages

If PKG_DEFAULT is set, and the package is set up for side-installation as
described above, dpkg-mkdeb generates a default package in addition to the
main package.  For a package named "pkg-v", version "r", and PKG_DEFAULT set
to "pkg", the default package is named "pkg", version "default-v-r".  The
default package includes a shadow lndir tree version of the package prefix
(e.g. "/usr/local/tools/icc") pointing to the main package prefix (e.g.
"/usr/local/tools/icc-10.1.011").  The rules for package dotkits and wrappers
apply to the default package, so in the example above, the dotkit will be named
"icc" and the icc wrapper will be named "icc".

### Package Dependencies

If your package requires other /usr/local packages to build,
PKG_BUILDREQUIRES should list those packages.  This ensures that the packages
you need are available during the build, and also that their dotkits
are loaded.

If your package requires other /usr/local packages to function at runtime,
PKG_DEPENDS should list those packages.   This prevents your package from
being installed without the packages it depends on, and also links the
dotkits so using your package will use the packages it depends on
(unless you disable that by putting 'decoupledk' in PKG_FLAGS).

### Package Test Scripts

A test script will be included in a package if it exists under the name
package.test in the package source materials during a dpkg-mkdeb(1) build.
When the package is installed, the test is installed as part of the package's
metadata.  The test may then be executed using the dpkg-runtests utility.

Test  scripts  are run with their current working directory set to a clean
subdirectory of /tmp and their output redirected to the file test.log inside
that directory.  The directory is removed on success, or retained for
examination otherwise.

The scripts' exit codes are used to determine the result: 0=success, 1=notrun,
2=failure.  All scripts should complete relatively quickly and not include
interactive or GUI components.

The test is run via dpkg-wrap so the package's dotkit is used and the package's
macro file  will  have  been  sourced, therefore  the test script should be
able to run the package's executables just as a user would, and may reference
any of the following macro file variables:
```
$dpkg_prefix
$dpkg_subpackage
$dpkg_name
$dpkg_version
$dpkg_arch
$dpkg_maintainer
$dpkg_short_description
$dpkg_section
$dpkg_depends
$dpkg_buildrequires
$dpkg_flags
$dpkg_subpackages
```
It is possible to unuse the package dotkit inside the test script with the
command unuse $dpkg_name.  This may  be useful  in  a  compiler test, for
example, to check behavior of compiler executables run without the compiler's
dotkit environment.

### Running Tests Before Installation

Test scripts can be run against installed packages using the dpkg-runtests
utility.  The dpkg-testdeb utility allows test scripts to be run prior to
installation.  The utility takes an argument of one or more .deb files, and
does the following

- Reinvokes itself under dpkg-tmplocal to get a user-writeable, temporary
  /usr/local
- Installs the package(s) given on the cmdline
- Runs 'apt-userinst -f' in order to fix up all package dependencies
- Runs dpkg-runtests against the installed packages

Obviously, dpkg-runtests only does something if you've created a
package.test for your package.

This can be a quick way to perform a sanity check on a .deb you've produced.
It at least verifies that dependencies are correct, and that any unit tests
in package.test run successfully.

Example:
```
grondo@stagg0 ~ >dpkg-testdeb -h
Usage: dpkg-testdeb [OPTIONS]... PKG [PKG]...
   -h, --help      Display this message.
   -v, --verbose   Verbose output.
   -V, --verify    Also run dpkg-verify against package(s).

grondo@stagg0 ~/proj/mvapich-0.9.9-r1760 >dpkg-testdeb mvapich-shmem-pathscale-0.9.9_1760.1chaos.snapshot.20080109103716_linux-amd64.deb
dpkg-testdeb: Installing mvapich-shmem-pathscale-0.9.9 in temporary /usr/local..
dpkg-testdeb: Fixing up dependencies...
dpkg-testdeb: Running dpkg-runtests on installed packages...
dpkg-runtests: mvapich-shmem-pathscale-0.9.9            ok
dpkg-runtests: Summary: all tests passed
dpkg-testdeb: Success
```
### Documentation Summary

Each package can list its included documentation in its PKG_doc variable.  The
format for each line is "Multi word description: path".  For example, the Intel
icc compiler package.conf sets
```
PKG_doc="Documentation Index:  ${docdir}/Doc_Index.htm"
```
PKG_doc may contain multiple lines by embedding \n's.
```
PKG_doc="\
Reference Manual:  ${docdir}/Ref_manual.htm\n\
User Manual: ${docdir}/User_manual.html"
```
A summary of packaged documentation (/usr/local/dpkg-db/doc.html) can be
generated by running dpkg-docreport as root.

### Direct Installation

Most software will install to a tmproot, e.g. a directory created during
package building which contains usr/local/.... After pkg_install() runs, this
directory is archived directly into the deb file.  GNU software make install
targets typically accept a DESTDIR=tmproot argument for this purpose. However,
some software wants to be installed directly to its destination.  There are two
options available to get around this.  One is to modify or recreate the
supplied installation script with one that understands the tmproot concept.
The other way is to create a private copy of /usr/local that is bind mounted
on top of the real one in the user's private namespace during package creation.

To use the latter method, include "notmproot" in PKG_FLAGS.  Then in your
pkg_install() function, you may ignore the tmproot argument $1 (which will be
set to "/") and install directly to /usr/local.  dpkg-mkdeb takes care of
setting up and tearing down the private copy of /usr/local using its
dpkg-tmplocal helper.  Since the bind mount is performed in a private
namespace, it is only visible to  you (and dpkg-mkdeb), not other users of
the system.

If PKG_BUILDREQUIRES lists any packages required at build time, these will be
installed into the private /usr/local prior to execution of the package's
pkg_build() and pkg_install() scripts.

### Interactive Installation Scripts

Some software ships with an interactive install program.  First, look for
command line arguments that can short circuit the interactive part.  If you
must provide input during installation and the input is gathered from your tty,
it may be possible to script it using the expect(1) language.  If the install
program starts a GUI, try unsetting your DISPLAY environment variable or
looking for options to install without the GUI.  If it is unavoidable to
install via a GUI, then you may have to install the package manually into a
mock /usr/local (see below) and copy the results into the package subversion
repo.

### Build Logs

Every package's build/install log is installed with the package in
```
/usr/local/dpkg-db/info/package.buildlog
```
It may be useful to review this log when diagnosing problems with installed packages.

It is possible to extract the log directly from a deb and review it with:
```
dpkg-deb --control file.deb
more DEBIAN/buildlog
```

### License Key Management

Some packages require access to a license key during installation.  You can
either embed the key in the package.conf (preferable if the key does not
expire) or reference LC license servers by including "license" in the
PKG_BUILDREQUIRES.  The latter means that packages can only be built inside
the LC firewall and should be avoided if at all possible.

### Vi Syntax Coloring for Package.conf Files

You can tell vi that package.conf is really a bash script by adding the following to your .vim/filetype.vim file:
```
if exists("did_load_filetypes")
  finish
endif
augroup filetypedetect
  au!  BufRead,BufNewFile package.conf   let g:is_bash=1 | setfiletype sh
augroup END
```
### Creating a Mock /usr/local for Testing

The dpkg-tmplocal and apt-userinst utilities can be used to create your own
version of /usr/local.  As previously discussed, dpkg-tmplocal spawns a shell
with an empty /usr/local mounted in place of the real /usr/local. Once you have
invoked dpkg-tmplocal, apt-userinst may be used to install any local .debs or
packages from the APT repository:
```
Usage: apt-userinst PKG [PKGS]...
   or  apt-userinst --fix-broken [PKGS]...
   or  apt-userinst --local-install [DEBS]...

  -h, --help           Display this message.
  -v, --verbose        Increase output verbosity.
  -l, --local-install  Install local packages (i.e. .debs, implies -f)
  -f, --fix-broken     Run apt-get(8) with -f argument to fix up missing
                       dependencies and broken packages in /usr/local.
```
Using these two tools, an entire, functional, /usr/local can be created with any packages
required for building and testing other packages or software. For example to install the
latest MVAPICH compiled with the Intel compilers:
```
grondo@stagg0 ~ >dpkg-tmplocal bash
grondo@stagg0 ~ >ls /usr/local
grondo@stagg0 ~ >apt-userinst mvapich-intel
apt-userinst: Attempting to initialize empty /usr/local
apt-userinst: Importing Builder GPG key
apt-userinst: Running apt-get update...
apt-userinst: Attempting to install: mvapich-intel
apt-userinst: Running apt-get -y install...
apt-userinst: Done.
grondo@stagg0 ~ >dpkg -l
Desired=Unknown/Install/Remove/Purge/Hold
| Status=Not/Installed/Config-files/Unpacked/Failed-config/Half-installed
|/ Err?=(none)/Hold/Reinst-required/X=both-problems (Status,Err: uppercase=bad)
||/ Name                            Version           Description
+++-===============================-=================-====================================================
ii  icc                             default-10.1.011- Intel C++ Compiler
ii  icc-10.1.011                    4                 Intel C++ Compiler
ii  ifort                           default-10.1.011- Intel Fortran Compiler
ii  ifort-10.1.011                  4                 Intel Fortran Compiler
ii  ld-auto-rpath                   1                 ld wrapper that adds --auto_rpath option
ii  license                         2.ocf             License configuration for LLNL OCF network
ii  mvapich-intel                   default-0.9.9-176 MVAPICH MPI for Intel compilers
ii  mvapich-intel-0.9.9             1760.4chaos.shmem MVAPICH MPI for Intel compilers
```

#### Package Use Logging

The automatically generated wrapper scripts and dotkits will log to the syslog local7.info channel each time they are used. Here is an example log entry from a gcc wrapper invocation:
```
Feb 22 10:59:19 mrhankey dpkg-wrapper: user=garlick pkg=gcc ver=default-4.1.2-2 pid=24654 cmd=gcc
```
While here are some log entries created by using/unusing the "icc" package,
which in turn loads the ld-auto-rpath package:
```
Feb 22 15:14:38 mrhankey dpkg-dotkit: user=garlick pkg=ld-auto-rpath ver=2 pid=3560 op=use
Feb 22 15:14:38 mrhankey dpkg-dotkit: user=garlick pkg=icc ver=default-9.1.052-4 pid=3560 op=use
Feb 22 15:14:40 mrhankey dpkg-dotkit: user=garlick pkg=ld-auto-rpath ver=2 pid=3560 op=unuse
Feb 22 15:14:40 mrhankey dpkg-dotkit: user=garlick pkg=icc ver=default-9.1.052-4 pid=3560 op=unuse
```
The goal is to centralize all of these logs across the center for data mining
by package maintainers.  Currently the OCF systems are aggregating these logs
in the global file system, accessible by members of the tools group:
```
/usr/global/tools/usage-logs/all_tools.log
```
A rotation/archival/reporting policy has not yet been developed for this log.

## /usr/local Packaging Best Practices

#### Packages should be self-contained
Packages should either contain all the parts they need to function, or be
explicitly dependent on other packages that complete them.  Packages that have
dependencies not expressed and contained within the packaging system may not
be transportable outside of the LC environment, e.g. to a vendor site during
acceptance testing or to a developer desktop.  Also, their unit tests may not
pass in the build farm.

#### Package Source Materials should be static for a given release
Package source materials should either be entirely contained within their
subversion repo (preferred), or should only be dependent on fairly static
external materials such as a URL to a versioned external download.  Builds can
only be reproduceable if a given subversion tag refers to a set of source
materials that never change under the tag.

#### No Unpackaged Updates to /usr/local
/usr/local is entirely owned by root:root, with file and directory modes 644
and 755.  Files in /usr/local should only change via the dpkg command, which
converts the mode and ownership of all packaged files to the above during
package installation.  Sudo can be used to extend dpkg privileges to non-root
users such as members of the Development Environment Group.  This ensures that
packaging discipline is maintained, while leaving policy for rollout practices
and schedules unaffected.

To list unpackaged files in /usr/local, run:
```
dpkg-nonpackaged [package] ...
```
To verify md5sums, mode, and ownership of packaged files, run:
```
   dpkg-verify [package] ...
```

#### Mount -o ro,nosuid
It is not safe to install/remove packages using dpkg from multiple systems
that mount the same /usr/local, so each instance of /usr/local should only
be writeable from one system.  It should be mounted with the ro option on
other systems.  Also, since setuid executables are not allowed by dpkg,
/usr/local should be mounted with the nosuid option for additional security.

#### Dotkits are Part of Package Metadata
Dotkits are automatically generated for each package as describted above.
It is possible to suppress or customize the dotkit, but do not do this unless
there is a compelling reason.  Sticking with the automatically generated dotkit
will result in a uniform environment for users.

#### Packages Include Embedded Unit Tests
See description above - tests are optional but including them is a good
practice.

#### Avoid Symlinks in /usr/local/bin to Commands in PATH
Symlinks for shells and interpreters should not be created in /usr/local/bin.
Users should leverage the PATH environment variable to select a reasonable
alternative.  In a "hash bang", use env(1), e.g. "#!/usr/bin/env perl".
Exceptions have been made for perl, bash, and tcsh links in
/usr/local/bin for historical reasons. Every effort should be made to avoid
further propagation of these historical artifacts in the future.

#### Avoid Wrapper Scripts that duplicate dotkit information
Use dpkg-wrap(8) in packaged wrappers, not explicit environment variable
settings that duplicate dotkit information.  In fact, use PKG_WRAPPERS to
generate your wrappers automatically as this will result in a uniform
environment for users.

#### Keep Package Contents Pristine
Default behavior should be preserved for software packages so that users are
not suprised by discrepencies if they use that package in a non-LC environment,
and they are able to use LC's environment to create portable and reusable
software.

#### Packages Should Explicitly Declare Dependencies
For the most part, packages should be self contained.  If they require
functionality from another package, they should list it in the PKG_DEPENDS
(runtime dependencies) or PKG_BUILDREQUIRES (build time dependencies) so that
dpkg(1) and dpkg-mkdeb(8) can manage these dependencies.  Packages should not
symlink to uncontrolled areas like home or application directories as this
makes the package vulnerable to falling apart if the files it depends on
change.  This is also true of system files, though dependencies on system
files are unavoidable, and in theory the system should be more stable due to
its own packaging discipline.

## References

- [The Debian GNU/Linux FAQ Chapter 7 - Basics of the Debian package management system](http://www.debian.org/doc/FAQ/ch-pkg_basics.en.html)
- [The Debian GNU/Linux FAQ Chapter 8 - The Debian package management tools](http://www.debian.org/doc/FAQ/ch-pkgtools.en.html)
- [Debian Policy Manual](http://www.debian.org/doc/debian-policy/index.html)
- [Linux Filesystem Hierarchy](http://tldp.org/LDP/Linux-Filesystem-Hierarchy/html/index.html)
- [LC Dotkit Reference](https://computing.llnl.gov/?set=jobs&page=dotkit)
