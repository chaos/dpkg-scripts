#!/bin/bash --posix

############################################################################
# Copyright (C) 2007 Lawrence Livermore National Security, LLC
# Produced at Lawrence Livermore National Laboratory.
# Written by Jim Garlick <garlick@llnl.gov>.
# UCRL-CODE-235516
# 
# This file is part of dpkg-scripts, a set of utilities for managing 
# packages in /usr/local with dpkg.
# 
# dpkg-scripts is free software; you can redistribute it and/or modify it 
# under the terms of the GNU General Public License as published by the Free
# Software Foundation; either version 2 of the License, or (at your option)
# any later version. 
#
# dpkg-scripts is distributed in the hope that it will be useful, but WITHOUT 
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or 
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for 
# more details.
#
# You should have received a copy of the GNU General Public License along
# with dpkg-scripts; if not, write to the Free Software Foundation, Inc.,
# 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA.
############################################################################

# constants
declare -r prog=`basename $0`
declare -r dpkgroot=/usr/local
declare -r dpkginit=/usr/sbin/dpkg-initialize
declare -r usage="\
Usage: ${prog} [OPTIONS]... PKG [PKG]...\n\
    -h, --help      Display this message.\n\
    -v, --verbose   Verbose output.\n\
    -V, --verify    Also run dpkg-verify against package(s)."

# user-supplied options
tmplocal=0
verify=0
verbose=0

############################################################################
#  Functions
############################################################################

die()
{
	echo  -e "${prog}: $@" >&2
    exit 1
}

log_msg()
{
    echo -e "${prog}: $@" >&2
}

log_verbose()
{
    [ $verbose = 1 ] && log_msg "$@"
}

package_name_list()
{
    local pkgs
    for file in $@; do
        pkgs="${pkgs:+$pkgs }$(dpkg-deb --field ${file} Package)" 
        [ $? -ne 0 ] && die "dpkg-deb on ${file} failed."
    done
    echo "$pkgs"
}

runcmd()
{
    local vopt=$verbose
    while getopts v opt; do
        case ${opt} in
            v) vopt=1 ;;
            *) die "runcmd internal error: Bad option: -${opt}" ;;
        esac
    done
    shift $((${OPTIND} - 1))

    log_verbose "Running $@"
    if [ $vopt = 1 ]; then
       $@ 
    else
       $@ >/dev/null 2>&1
    fi
}

############################################################################
#  Main script
############################################################################

# abort early if root
[ `id -u` = 0 ] && die "Do not run as root."

# process options
saved_args=$@
args=`/usr/bin/getopt -uo htVv -l help,tmplocal,verbose,verify -n ${prog} -- $@`
if [ $? -ne 0 ]; then
   die "$usage"
fi

set -- ${args}
while true; do
    case "$1" in
     -h|--help)     echo -e "$usage"; exit 0;;
	 -t|--tmplocal) tmplocal=1; shift;; 
     -V|--verify)   verify=1; shift;;
     -v|--verbose)  verbose=1; shift;;
	 --)            shift; break;;
	 *)             die "Internal error: option '$1' not understood" ;;
	esac
done

[ $#  -gt 0 ] ||  die "Must supply a package to test.\n$usage"

# 
#  If not running in tmplocal reinvoke under dpkg-tmplocal(8)
#
if [ $tmplocal = 0 ]; then
   exec dpkg-tmplocal -- $0 --tmplocal ${saved_args}
fi

#
#  Initialize tmplocal
#
$dpkginit || die "Failed to initialize tmp /usr/local. Did dpkg-tmplocal fail?"

#
#  Get package names for later use in dpkg-runtests
#
packages=$(package_name_list "$@") || die "Failed to read all packages"
log_msg "Installing ${packages} in temporary /usr/local..."

# 
#  Run dpkg to install packages. Expect failure here as there may
#   be missing dependencies which apt-get -f install will fix up.
# 
PATH=/sbin:/usr/sbin:$PATH runcmd dpkg --force-not-root -i "$@" 

#
#  Run 'apt-get -f install'
#
log_msg "Fixing up dependencies..."
runcmd apt-userinst -f               || die "apt-userinst failed"

#
#  Run tests for installed packages
#
log_msg "Running dpkg-runtests on installed packages..."
runcmd -v dpkg-runtests ${verbose+-v }${packages}  || die "dpkg-runtests failed"

#
#  Run dpkg-verify if requested
#
if [ $verify = 1 ]; then
   log_msg "Running dpkg-verify on installed packages..."
   runcmd -v dpkg-verify ${packages} || die "dpk-verify failed"
fi

log_msg "Success"
exit 0

# vi: ts=4 sw=4 expandtab
