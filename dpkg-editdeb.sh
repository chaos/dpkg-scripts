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

declare -r prog=dpkg-editdeb
declare -r dpkgroot=/usr/local
tmpdir=""

die()
{
    echo "${prog}: $1" >&2
    if [ -n "${tmpdir}" ]; then
        rm -rf ${tmpdir}
    fi
    exit 1
}

if [ $# != 1 ]; then
    echo "Usage: dpkg-editdeb.sh debfile" >&2
    exit 1
fi
debfile=$1
debbase=$(basename ${debfile})
debdir=$(dirname ${debfile})

[ $(id -u) = 0 ] && die "you must not edit debs as superuser"
umask 022
if ! echo $PATH | grep -q ${dpkgroot}/bin; then
    PATH=$PATH:${dpkgroot}/bin
fi

tmpdir=$(mktemp -d)

cp ${debfile} ${tmpdir} 2>/dev/null || die "could not read ${debfile}"
pushd ${tmpdir}
  ar x ${debbase} || die "failed to extract deb archive"

  mkdir -p root/DEBIAN
  tar -pxzf control.tar.gz -C root/DEBIAN || die "failed to extract control"
  tar -pxzf data.tar.gz -C root || die "failed to extract data"
  cp -r root root.orig

  pushd root
  echo "Type exit to save changes, or exit 1 to abort." >&2
  bash  || die "aborted"
  popd

  diff -rNq root.orig root && die "deb file is unchanged"

  # force revision change
  version=$(awk '/^Version:/ { print $2 }' root/DEBIAN/control)
  ver=$(echo ${version} | cut -d- -f1)
  rev=$(echo ${version} | cut -d- -f2)
  version=${ver}.${rev}.edited.$(date +%Y%m%d%H%M%S)
  sed -i "s/Version:.*/Version: ${version}/" root/DEBIAN/control
popd
  # write file to same dir as source
  # name will be different due to revision change
  echo debdir is ${debdir}
  dpkg-deb --build ${tmpdir}/root ${debdir} || die "dpkg-deb failed"
rm -rf ${tmpdir}
exit 0

# vi: expandtab sw=4 ts=4

