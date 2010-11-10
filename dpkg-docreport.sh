#!/bin/bash --posix
# create html index to package documentation

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

declare -r prog=dpkg-docreport
declare -r dpkgroot=/usr/local
declare -r infodir=${dpkgroot}/dpkg-db/info
declare -r docsummary=${dpkgroot}/dpkg-db/doc.html

die()
{
    echo "${prog}: $1" >&2
    exit 1
}

get_arch()
{
    dpkg-architecture | grep DEB_BUILD_ARCH= | cut -d= -f2
}

emit_opening()
{
    cat <<EOT
<html>
<head> 
  <title> packages installed in /usr/local</title> 
</head>
<body>
  <h2> Packages Installed in /usr/local</h2>
  Report generated $(date)
  <table cellspacing="0" cellpadding="0" border="1">
  <thead>
    <tr>
    <th>Package</th>
    <th>Description</th>
    <th>Web docs</th>
    <th>Man</th>
    <th>Info</th>
    <th>Dotkit</th>
    </tr>
  </thead>
  <tbody>
EOT
}

emit_closing()
{
    cat <<EOT2
  </tbody>
  </table>
</body>
</html>
EOT2
} 

# Turn doc entries formatted thus:
#   "Description maybe with spaces: /full/path/to/file" 
# into html on stdout.
doc2html()
{
    local docfile=${infodir}/$1.doc
    if [ -r ${docfile} ]; then
        sed 's/\([^:]*\):[ \t]*\(.*\)$/<a href="file:\/\/\2">\1<\/a><br>/' ${docfile}
    fi
}

man_yn()
{
    if dpkg -L $1 | grep /man/ >/dev/null; then
        echo 'Y'
    else
        echo 'N'
    fi
}

texi_yn()
{
    if dpkg -L $1 | grep /info/ >/dev/null; then
        echo 'Y'
    else
        echo 'N'
    fi
}

dotkit_yn()
{
    if [ -f ${infodir}/$1.dk ]; then
        echo 'Y'
    else
        echo 'N'
    fi
}

rowcounter=0

emit_row()
{
    local pkg=$1
    local desc=$(dpkg-query --show --showformat '${Description}' $pkg)
    local vers=$(dpkg-query --showformat '${version}' --show ${pkg})

    if [ ${rowcounter} = 0 ]; then
        rowcounter=1
        echo '<tr>'
    else
        rowcounter=0
        #echo '<tr class="greenbar">'
        echo '<tr bgcolor="#CCCCCC">'
    fi
    echo '<th><p>'${pkg}-${vers}'</p></th>'
    echo '<td>'${desc}'</td>'
    echo "<td>$(doc2html ${pkg})</td>"
    echo "<td>$(man_yn ${pkg})</td>"
    echo "<td>$(texi_yn ${pkg})</td>"
    echo "<td>$(dotkit_yn ${pkg})</td>"
    echo '</tr>'
}

if [ $# -gt 0 ]; then
    echo "Usage: ${prog}" >&2
    exit 1
fi

[ $(id -u) != 0 ] && die "you must make docreport as superuser"
umask 022
if ! echo $PATH | grep -q ${dpkgroot}/bin; then
    PATH=$PATH:${dpkgroot}/bin
fi

emit_opening >${docsummary}

for package in $(dpkg-query --show --showformat '${package}\n'); do
    emit_row ${package} >>${docsummary}
done

emit_closing >>${docsummary}

exit 0

# vi: expandtab sw=4 ts=4

