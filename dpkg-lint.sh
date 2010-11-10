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

declare -r prog=dpkg-lint
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

warn()
{
    echo "${prog}: WARN: $1" >&2
}

err()
{
    echo "${prog}: ERROR: $1" >&2
}

valid_arch()
{
    local arch

    [ "$1" = "all" ] && return 0
    for arch in $(dpkg-architecture -L); do
        [ "$1" = "${arch}" ] && return 0
    done
    return 1
}

lint_control()
{
    local file basefile arch

    # detect any missing metadata files
    [ -f DEBIAN/control ] || error "missing control file"
    [ -f DEBIAN/md5sums ] || warn "missing md5sums file"
    [ -f DEBIAN/test ] || warn "missing test file"
    [ -f DEBIAN/doc ] || warn "missing doc file"
    [ -f DEBIAN/buildlog ] || warn "missing buildlog file"
    [ -f DEBIAN/buildinfo ] || warn "missing buildinfo file"
    # detect any "extra" metadata files
    for file in $(find DEBIAN -type f); do
        basefile=$(basename ${file})
        case ${basefile} in
            control|conffiles|preinst|postinst|prerm|postrm)
		;;
	    md5sums|test|doc|buildlog|buildinfo)
		;;
	    *) 	
		warn "unknown metadata file: ${basefile}"
                ;;
        esac
    done
    # find missing mandatory control file tags
    grep -q "^Package:" DEBIAN/control \
		|| err "control file missing Package tag"
    grep -q "^Version:" DEBIAN/control \
		|| err "control file missing Version tag"
    grep -q "^Maintainer:" DEBIAN/control \
		|| err "control file missing Maintainer tag"
    grep -q "^Description:" DEBIAN/control \
		|| err "control file missing Description tag"
    grep -q "^Architecture:" DEBIAN/control \
		|| err "control file missing Architecture tag"
    # warn if snapshot/test build
    version=$(awk '/^Version:/ { print $2 }' DEBIAN/control)
    echo ${version} | egrep -q "edited|snapshot" && warn "snapshot/edited build"
    # detect bad Architecture name
    arch=$(awk '/^Architecture:/ { print $2 }' DEBIAN/control)
    valid_arch ${arch} || err "invalid architecture: ${arch}"
    # TODO: find invalid local doc references
    # TODO: unsigned package
    # TODO: files contains files not in md5sums (skip dirs)
}

lint_data()
{
    local file

    # detect files outside of /usr/local
    for file in $(find . -print); do
        case ${file} in
            .|./usr|./usr/local|./usr/local/*|./DEBIAN|./DEBIAN/*) 
		;;
	    *)
        	err "illegal file pathname: ${file}"
		;;
        esac
    done
    # detect files with improper mode bits
    for file in $(find . -name DEBIAN -prune -o -perm +7000 -print); do
        err "[ugo+st] ${file}"
    done
    for file in $(find . \( -name DEBIAN -o -type l \) -prune -o -perm +022 -print); do
        warn "[go+w] ${file}"
    done
    for file in $(find . -name DEBIAN -prune -o ! -perm +005 -print); do
        warn "[u-rx] ${file}"
    done
    # TODO: optdir/package without -version
    # TODO: doc/package-version
    # TODO: creates a "share" directory
    # TODO: creates a top level /usr/local directory
    # TODO: creates a subdir in /usr/local/bin
    # TODO: missing dotkit
    # TODO: symlinks outside of /usr/local
    # TODO: executable name conflicts with a common system util
}

lint()
{
    lint_control
    lint_data
}

##
## MAIN
## 

[ $(id -u) = 0 ] && die "you must not check packages as superuser"
umask 022
if ! echo $PATH | grep -q ${dpkgroot}/bin; then
    PATH=$PATH:${dpkgroot}/bin
fi

if [ $# != 1 ]; then
    echo "Usage: dpkg-lint debfile" >&2
    exit 1
fi


debfile=$1
debbase=$(basename ${debfile})
tmpdir=$(mktemp -d)
cp ${debfile} ${tmpdir} 2>/dev/null || die "could not read ${debfile}"
pushd ${tmpdir} >/dev/null
  ar x ${debbase} || die "failed to extract deb archive"
  mkdir -p root/DEBIAN
  tar -pxzf control.tar.gz -C root/DEBIAN || die "failed to extract control"
  tar -pxzf data.tar.gz -C root || die "failed to extract data"
  (cd root && lint)
popd >/dev/null
rm -rf ${tmpdir}
exit 0

# vi: expandtab sw=4 ts=4

