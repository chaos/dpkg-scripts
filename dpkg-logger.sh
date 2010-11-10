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
# dpkg-logger - log package activity (called by dpkg-wrap and package dotkits)
#
declare -r prog=dpkg-logger
declare -r syslog_pri=local7.info
declare -r infodir="/usr/local/dpkg-db/info"
Dopt=0

PATH=/usr/bin:/bin:$PATH

die()
{
    echo "${prog}: $1" >&2
    exit 1
}

while getopts "p:wdD" opt; do
    case ${opt} in
        p) dpkg_name=${OPTARG} ;;
        w) tag=dpkg-wrapper ;;
        d) tag=dpkg-dotkit ;;
        D) Dopt=1 ;;
        *) die "bad option: ${opt}" ;;
    esac
done
shift $((${OPTIND} - 1))
[ -n "${tag}" ] || die "you must specify -w or -d for wrapper or dotkit"

[ -n "${dpkg_name}" ] || die "you must specify -p package"

# get $dpkg_version set
if [ -r ${infodir}/${dpkg_name}.macros ]; then
    . ${infodir}/${dpkg_name}.macros
fi

# dpkg-wrap will use/unuse dotkit, then call dpkg-logger, so suppress
# logging via dotkit or we will have three log entries!
if [ "${tag}" = "dpkg-wrapper" ] || [ "${_dpkg_wrap}" != "${dpkg_name}" ]; then
    message="user=$(id -un) pkg=${dpkg_name} ver=${dpkg_version}"
    if [ ${Dopt} = 1 ]; then
        echo ${tag}: ${message} "$@"
    else
        /usr/bin/logger -p ${syslog_pri} -t ${tag} -- ${message} "$@"
    fi
fi
exit 0
