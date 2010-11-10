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
#
# dpkg-wrap - run a command in its packaged dotkit environment
#
declare -r prog=dpkg-wrap
declare -r dkinit=/usr/share/dpkg-dotkit/init
declare -r syslog_pri=local7.info
declare -r infodir=/usr/local/dpkg-db/info

die()
{
    echo "${prog}: $*" >&2
    exit 1
}

split ()
{
    local word
    (IFS=$IFS","; for word in $*; do echo $word; done)
}

# Test for presence of package option
#  Usage: get_pkg_opt option
get_pkg_opt ()
{
    local opt

    for opt in $(split ${dpkg_flags}); do
        [ ${opt} = $1 ] && return 0
    done
    return 1
}


if [ $# -lt 2 ]; then
    echo "Usage: ${prog} package cmd [args...]" >&2
    exit 1
fi
pkg=$1; shift
cmd=$1; shift

if ! [ -f ${dkinit} ]; then
    die "${dkinit}: not found: dpkg-dotkit RPM not installed?"
fi
if [ "${_dpkg_wrap}" = "${pkg}" ]; then
    die "cowardly refusing to recurse within a dpkg wrapper script"
fi
# _dpkg_wrap
export _dpkg_wrap=${pkg}

# initialize dotkit, discarding any existing dotkit state
unset DK_ROOT
unset DK_NODE
unset DK_SUBNODE
unset _dk_inuse
eval $(${dkinit} -b)

# load package macros for test scripts running under dpkg-wrap
if [ -r ${infodir}/${pkg}.macros ]; then
    . ${infodir}/${pkg}.macros
fi

# "use" the package's dotkit (will not log due to $_dpkg_wrap setting)
use -q ${pkg} 2>/dev/null
[ $? = 4 ] && die "wrapped package has no dotkit"


if get_pkg_opt verboselog; then
    /usr/bin/dpkg-logger -p ${pkg} -w pid=$$ cmd=$cmd $@
else
    /usr/bin/dpkg-logger -p ${pkg} -w pid=$$ cmd=$cmd
fi

# exec the command 
exec ${cmd} "$@"
