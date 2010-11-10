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

# A package exports a single executable shell script called 'test' as part
# of its metadata.  The test exits with 0=success, 1=notrun, >1=fail.
# It may log to stdout/stderr.

declare -r prog=dpkg-runtests
declare -r dpkgroot=/usr/local
declare -r infodir=${dpkgroot}/dpkg-db/info
declare -r dkwrap=/usr/bin/dpkg-wrap

vopt=0
Vopt=0

die()
{
    echo "${prog}: $1" >&2
    exit 1
}


runtest()
{
    local pkg=$1
    local result

    echo "start $(date)"
    echo "running dpkg -s ${pkg}"
    dpkg -s ${pkg}
    #echo "running dpkg-verify ${pkg}"
    #dpkg-verify ${pkg} && echo "dpkg-verify reports no errors"
    if [ -r ${infodir}/${pkg}.dk ] && [ -x ${dkwrap} ]; then
        echo "running ${dkwrap} ${pkg} ${infodir}/${pkg}.test"
        ${dkwrap} ${pkg} ${infodir}/${pkg}.test
    else
        echo "running ${infodir}/${pkg}.test"
        ${infodir}/${pkg}.test
    fi
    result=$?
    case ${result} in
        0) 	echo "result: ok" 
		;;
        1) 	echo "result: notrun" 
		;;
        *) 	echo "result: fail" 
		;;
    esac
    echo "finish $(date)"

    return ${result}
}

usage()
{
    echo "Usage: dpkg-runtests [-v] pkg [pkg...]" >&2
    exit 1
}

##
## MAIN 
##

while getopts "?vV" opt; do
    case ${opt} in
        h|\?) usage ;;
        v) vopt=1 ;;
        V) Vopt=1; vopt=1 ;;
        *) die "bad option: ${opt}" ;;
    esac
done
shift $((${OPTIND} - 1))

failures=0
testsrun=0

[ $(id -u) != 0 ]  || die "you must not run tests as superuser"
umask 022

packages=$(dpkg-query -Wf '${package} ${status}\n' "$@" \
         | awk '$4 == "installed" {print $1}' )

workdir=$(mktemp -d ${TMPDIR:-/tmp}/${prog}.XXXXXXXXXX) || die "mktemp error"

for pkg in ${packages}; do
    if ! dpkg -L ${pkg} >/dev/null 2>&1; then
        printf "${prog}: %-40s %s\n" ${pkg} "error - no such package" >&2
        continue 
    fi
    if ! [ -x ${infodir}/${pkg}.test ]; then
        printf "${prog}: %-40s %s\n" ${pkg} "notest"
        continue
    fi
    tmpdir=${workdir}/${pkg}
    mkdir ${tmpdir} || die "Failed to create tmpdir ${tmpdir}"
    printf "${prog}: %-40s " ${pkg}
    pushd ${tmpdir} >/dev/null
       runtest ${pkg} >test.log 2>&1 
       result=$?
    popd >/dev/null
    case $result in
        0)	printf "ok\n"
        	testsrun=$(expr ${testsrun} + 1)
            [ $Vopt = 1 ] && cat ${tmpdir}/test.log
		    rm -rf ${tmpdir}
		;;
        1)	printf "notrun (see %s)\n" ${tmpdir}
            [ $vopt = 1 ] && cat ${tmpdir}/test.log
		;;
        2) 	printf "failed (see %s)\n" ${tmpdir}
            [ $vopt = 1 ] && cat ${tmpdir}/test.log
        	failures=$(expr ${failures} + 1)
        	testsrun=$(expr ${testsrun} + 1)
		;;
    esac
done

rmdir ${workdir} 2>/dev/null

if [ ${failures} = 0 ]; then
    echo "${prog}: Summary: all tests passed"
else
    echo "${prog}: Summary: ${failures} of ${testsrun} tests failed"
    exit 2
fi

exit 0

# vi: expandtab sw=4 ts=4
