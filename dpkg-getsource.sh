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
declare -r prog=dpkg-getsource
declare -r dpkgroot=/usr/local
declare -r dpkg_infodir=${dpkgroot}/dpkg-db/info

die()
{
    echo "${prog}: $1" >&2
    exit 1
}

warn()
{
    echo "${prog}: $*" >&2
}

get_build_source()
{
    local buildinfo=${dpkg_infodir}/$1.buildinfo

    if [ -r ${buildinfo} ]; then
        awk '/^Source:/ { print $2 }' ${buildinfo}
        return 0
    fi
    return 1
}

usage()
{
    echo "Usage: ${prog} packagename" >&2
    exit 1
}

#
# MAIN
#

[ $# = 1 ] || usage
package=$1

buildsrc=$(get_build_source ${package})
[ $? = 0 ] || die "package \"${package}\" is not installed"

# must be a svn url
if ! echo ${buildsrc} | grep -q "://"; then
    die "Package source ``${buildsrc}'' is not a URL"
fi
# must be a tag (or it may not match package!)
if ! echo ${buildsrc} | grep -q "/tags/"; then
    die "Package source ``${buildsrc}'' is not a subversion tag"
fi

# probably a tag in package_version format
dirname=$(basename ${buildsrc})
# prepend package_ if not embedded (maybe unexpected tag format)
if ! echo ${dirname} | grep -q ${package}; then
    dirname=${package}_${dirname}
fi
[ -d ${dirname} ] && die "${dirname} directory exists"

warn "exporting ${package} to ${dirname}"
svn export ${buildsrc} ${dirname}
[ $? = 0 ] || die "svn export failed"

exit 0
