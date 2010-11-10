#!/bin/bash --posix

############################################################################
# Copyright (C) 2007-2008 Lawrence Livermore National Security, LLC
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
declare -r prog=dpkg-mkdeb
declare -r dpkgroot=/usr/local
declare -r dpkg_infodir=${dpkgroot}/dpkg-db/info
declare -r dkinit="/usr/share/dpkg-dotkit/init -b"

# Paths
if ! workdir=$(mktemp -d ${TMPDIR:-/tmp}/${prog}.XXXXXXXXXX); then
    echo "mktemp failed" >&2
    exit 1
fi
tmpsrc="${workdir}/src"
pkgconf="${workdir}/package.conf"
buddha="${workdir}/META"
tmproot="${workdir}/root-main"
savedtmproot=""                 # save ${tmproot} in case we have to move it
tmproot2="${workdir}/root-dflt"
tmpout="${workdir}/build.log"   

# Args related globals
buildsrc=""                     # path/URL to original package source
snapshot=$(date +%Y%m%d%H%M%S)  # snapshot string (NULL if not a snapshot build)
subpackage=""                   # subpackage we are building (if any)
variant=""                      # variant we are building (if any)
vopt=0                          # -v   verbose flag
fopt=0                          # -f   force overwrite deb flag
uopt=0                          # -u   secret restart flag
popt=""                         # -p package.conf
mopt=""                         # -m metafile
kopt=0                          # -k   keep build dir
topt=0                          # -t   don't use tmplocal unless notmproot
query=""                        # -q   query package information
outfile=""                      # main package deb file
outfile2=""                     # default package deb file
selfpath="dpkg-mkdeb"
argscpy=""                      # copy of args for restart

#############################################################################
# general support functions
#############################################################################

# Cleanup temporary files/directories, if any
cleanup()
{
    if [ ${kopt} = 0 ]; then
        rm -rf ${workdir}
    else
        warn "work directory preserved: ${workdir}"
    fi
} 

clean_exit ()
{
    cleanup
    exit $1
}

# Print message on stderr, cleanup, then exit
# If no -v, spew forth any reserved output for debugging.
die()
{
    echo ${prog}: $* >&2
    clean_exit 1
}

# Print message on stderr
warn()
{
    echo ${prog}: $* >&2
}


# split comma or space-separated words
split ()
{
    local word
    (IFS=$IFS","; for word in $*; do echo $word; done)
}

# match glob ($1) against remaining args
match_glob ()
{
    local glob=$1; shift
    local result=1 # no match
    local dir 

    if dir=$(mktemp -d); then
        pushd ${dir} >/dev/null
            touch "$@"
            if [ -f "${glob}" ]; then
                result=0 # direct match
            elif [ "$(echo -n ${glob})" != "${glob}" ]; then
                result=0 # globbed match
            fi
        popd >/dev/null
        rm -rf ${dir}
    fi
    return $result
}

# Turn dirname into a fully qualified path on stdout.
#  Usage: fullpath dirname
fullpath()
{
    case $1 in
        /*) echo $1 ;;
        .) echo $(pwd) ;;
        ./*) echo $(pwd)/$(echo $1|sed 's/\.\///') ;;
        *) echo $(pwd)/$1 ;;
    esac
}

# Get system build architecture from 'dpkg-architecture' (part of dpkg)
get_build_arch ()
{
    local arch=$(dpkg-architecture | grep DEB_BUILD_ARCH= | cut -d= -f2)

    if [ -z "${arch}" ]; then
        warn "could not determine build arch"
        return 1
    fi
    echo ${arch}
}

# Verify that a package build requirement is satisfied.
checkreq ()
{
    local pkg

    if echo $1 | grep -q "=" ; then # handle [=version] (glob OK)
        for pkg in $(dpkg-query -Wf '${Package}=${Version}\n'); do
            match_glob $1 ${pkg} && return 0
        done 
    else
        for pkg in $(dpkg-query -Wf '${Package}\n${Provides}\n'); do
            [ ${pkg} = $1 ] && return 0
        done
    fi
    return 1
}

get_tmproot ()
{
    if [ $# = 1 ] && [ "$1" = "-d" ]; then
        echo ${tmproot2}
    else
        echo ${tmproot}
    fi
}

#############################################################################
# package.conf accessors, etc
#############################################################################

# Parse build-buddah META file and set meta_* vars for each field
#  Usage: set_meta (in a subshell!)
set_meta ()
{
    local line key val

    if [ -r "${buddha}" ]; then
        eval $(cat ${buddha} | while read line; do
            line=$(echo $line | sed -e 's/#.*$//')
            if [ -n "${line}" ]; then
                key=$(echo $line | cut -d: -f1 | sed -e 's/[ \t]*//')
                val=$(echo $line | cut -d: -f2 | sed -e 's/^[ \t]*//')
                echo meta_$(echo $key | tr [:upper:] [:lower:])=\"$val\"
            fi
        done)
    fi
}

# Parse package.conf and return value for specified variable (undef is error).
# If buddha META file is present, parse it first so meta_* values can be used.
#  Usage: get_pkg_var var
get_pkg_var ()
{
    local tmp=$(set_meta && source ${pkgconf} >/dev/null && eval echo \$$1)

    [ -n "${tmp}" ] || return 1
    echo -e ${tmp}
}

# Same as get_pkg_var but warn if undefined
#  Usage: get_pkg_var_req var
get_pkg_var_req ()
{
    local tmp

    if ! tmp=$(get_pkg_var $1); then
        warn "$1 not found in package.conf (required)"
        return 1
    fi
    echo ${tmp}
}

# Extract the base name of a side installed package
get_pkg_basename ()
{
    get_pkg_var_req PKG_NAME | sed  -e 's/-[0-9].*//'
}

# Extract the base version of a side installed package
get_pkg_basever ()
{
    local base name

    base=$(get_pkg_basename) || return 1
    name=$(get_pkg_var_req PKG_NAME) || return 1
    echo ${name} | sed -e "s/${base}//" -e 's/^-//'
} 

# Construct package name
#  Usage: make_pkg_name [-d] [subpackage]
make_pkg_name ()
{
    local name base bver res
    local dflt=0 sub=""

    while [ $# -gt 0 ]; do 
        case $1 in
            -d) dflt=1; shift ;;
            -*) warn "make_pkg_name: bad option: $1"; return 1 ;;
            *) sub=$1; shift ;;
        esac
    done

    name=$(get_pkg_var_req PKG_NAME) || return 1
    base=$(get_pkg_basename) || return 1

    # From debian policy manual:
    #  Package names must consist only of lower case letters (a-z), 
    #  digits (0-9), plus (+) and minus (-) signs, and periods (.). 
    #  They must be at least two characters long and must start with 
    #  an alphanumeric character.
    if echo ${name} | grep -q '[/_!@#$%^&*()=<>]'; then
        warn "PKG_NAME allows only alphanumeric, plus (+), minus (-), and period (.) chars"
        return 1
    fi
    # NOTE: apt presumes lower case
    if echo ${name} | grep -q '[A-Z]'; then
        warn "PKG_NAME alpha chars should be lower case"
        return 1
    fi
    if [ $(echo -n ${name} | wc -c) -lt 2 ]; then
        warn "PKG_NAME should be at least two characters long"
        return 1
    fi

    res=${base}${sub:+"-${sub}"}
    if [ ${dflt} = 1 ]; then
        res=${res}
    else
        bver=$(get_pkg_basever) || return 1
        res=${res}${bver:+"-${bver}"}
    fi
    echo ${res}
    return 0
}

# Get package name, modified if building subpackage
#  Usage: get_pkg_name [-d]
get_pkg_name ()
{
    make_pkg_name $* ${subpackage}
}

# Get package version, modified if building a snapshot or variant
#  Usage: get_pkg_version [-d]
get_pkg_version ()
{
    local ver res

    ver=$(get_pkg_var_req PKG_VERSION) || return 1
    if echo ${ver} | grep -q "_"; then
        warn "``_'' is illegal in PKG_VERSION"
        return 1
    fi

    res=${ver}
    if [ $# = 1 ] && [ "$1" = "-d" ]; then
        res=default-$(get_pkg_basever)-${res} || return 1
    fi
    res=${res}${variant:+".${variant}"}
    res=${res}${snapshot:+".snapshot.${snapshot}"}
    echo ${res}
}

# Query package names in name_version form.  Leave variants out of it
# unless a single ${variant} is defined via command line.
#  Usage: list_pkg_names [-d]
list_pkg_names ()
{
    local subs sub ver

    if [ "$1" = "-d" ]; then
        get_pkg_var PKG_DEFAULT >/dev/null || return
    fi

    subs=$(get_pkg_var PKG_SUBPACKAGES);
    ver=$(get_pkg_version $*) || exit 1

    if [ -n "${subs}" ]; then
        for sub in $(split ${subs}); do
            echo $(make_pkg_name $* ${sub})_${ver}
        done
    else
        echo $(make_pkg_name $*)_${ver}
    fi
}

# Get package prefix. 
#  Usage: get_pkg_prefix [-d]
get_pkg_prefix ()
{
    local name=$(get_pkg_name $*) || return 1

    case "$(get_pkg_var_req PKG_SECTION)" in
        root)  echo ${dpkgroot} ;;
        tools) echo ${dpkgroot}/tools/${name} ;;
        storage) echo ${dpkgroot}/storage/${name} ;;
        viz) echo ${dpkgroot}/viz/${name} ;;
        opt)   echo ${dpkgroot}/opt/${name} ;;
        *)     warn "invalid PKG_SECTION"; return 1 ;;
    esac
}

# Set macros used in package.conf
#  Usage: set_macros [-d] (in a subshell!)
set_macros ()
{
    local pfx name

    name=$(get_pkg_name $*) || return 1
    pfx=$(get_pkg_prefix $*) || return 1

    prefix=${pfx}
    bindir=${pfx}/bin
    etcdir=${pfx}/etc
    mandir=${pfx}/man
    infodir=${pfx}/info
    docdir=${pfx}/doc
    sbindir=${pfx}/sbin
    includedir=${pfx}/include
    libdir=${pfx}/lib
    libexecdir=${pfx}/libexec
    srcdir=${pfx}/src
    vardir=${pfx}/var
    lbindir=${dpkgroot}/bin
    dotkitdir=${dpkgroot}/etc/dotkit
    lccdir=${dpkgroot}/etc/lcc
    pkgname=${name}
    # provide default PKG_ARCH value in case undefined
    PKG_ARCH=$(get_pkg_arch)
}

# Like get_pkg_var except define macros prior to sourcing the file.
#  Usage: get_pkg_var_withmacros [-d] var
get_pkg_var_withmacros ()
{
    local tmp

    if [ $# = 2 ] && [ $1 = "-d" ]; then
        tmp=$(set_meta; set_macros -d; source ${pkgconf} >/dev/null; eval echo \$$2)
    else
        tmp=$(set_meta; set_macros; source ${pkgconf} >/dev/null; eval echo \$$1)
    fi

    [ -z "${tmp}" ] && return 1
    echo -e ${tmp}
}

# Get package arch
#  Usage: get_pkg_arch
get_pkg_arch ()
{
    local arch buildarch

    buildarch=$(get_build_arch) || return 1

    if arch=$(get_pkg_var PKG_ARCH); then
        if [ "${arch}" != "all" ] && [ "${buildarch}" != "${arch}" ]; then
            warn "PKG_ARCH should be set to all or ${buildarch} to build here"
            return 1
        fi
    else
        arch=${buildarch}
    fi
    echo ${arch}
}

# Test for presence of package option
#  Usage: get_pkg_opt option
get_pkg_opt ()
{
    local flags opt

    flags=$(get_pkg_var PKG_FLAGS) || return 1

    for opt in $(split ${flags}); do
        [ ${opt} = $1 ] && return 0
    done
    return 1
}


list_variants ()
{
    local names

    names=$(get_pkg_var PKG_VARIANTS) || return 1
    split ${names}
    return 0
}

# List packages this package depends on
list_depends ()
{
    local deps pkg 

    deps=$(get_pkg_var PKG_DEPENDS) || return 0
    if echo ${deps} | grep -q '|'; then
        warn "can't handle |'s in PKG_DEPENDS with auto-generated dotkits yet "
        return 1
    fi

    # drop the (version) from package name for dotkit processing
    for pkg in $(split ${deps}); do
        echo $pkg | sed -e 's/(.*)//g' 
    done
}

# Query data about a package
query_vars ()
{
    local var result

    if [ "$1" = "all" ]; then
        set - "name version basename basever subpackages variants buildrequires names default"
    fi
    for var in $*; do
        case ${var} in
            subpackages)   result=$(split $(get_pkg_var PKG_SUBPACKAGES)) ;;
            variants)      result=$(split $(get_pkg_var PKG_VARIANTS)) ;;
            buildrequires) result=$(get_pkg_var PKG_BUILDREQUIRES) ;;
            name)          result=$(get_pkg_var PKG_NAME) ;;
            version)       result=$(get_pkg_var PKG_VERSION) ;;
            names)         result=$(list_pkg_names) ;;
            basename)      result=$(get_pkg_basename) ;;
            basever)       result=$(get_pkg_basever) ;;
            default)       result=$(list_pkg_names -d) ;;
            *) die "unknown field '${var}'" ;;
        esac
        echo ${var}: ${result}
    done
}

#############################################################################
# package metadata processing
#############################################################################

# Make macros macros file
#  Usage: make_macros [-d] (in a subshell!)
make_macros ()
{
    local pfx name vers arch maint desc section depends buildrequires
    local flags subpackages variants default

    pfx=$(get_pkg_prefix $*) || return 1
    name=$(get_pkg_name $*) || return 1
    vers=$(get_pkg_version $*) || return 1
    arch=$(get_pkg_arch) || return 1
    maint=$(get_pkg_var_req PKG_MAINTAINER) || return 1
    desc=$(get_pkg_var_req PKG_SHORT_DESCRIPTION) || return 1
    section=$(get_pkg_var_req PKG_SECTION) || return 1
    depends=$(get_pkg_var PKG_DEPENDS)
    buildrequires=$(get_pkg_var PKG_BUILDREQUIRES)
    flags=$(get_pkg_var PKG_FLAGS)
    subpackages=$(get_pkg_var PKG_SUBPACKAGES)
    variants=$(get_pkg_var PKG_VARIANTS)
    default=$(get_pkg_var PKG_DEFAULT)

    echo export dpkg_prefix=${pfx}
    echo export dpkg_subpackage=${subpackage}
    echo export dpkg_variant=${variant}
    echo export dpkg_default=${default}

    echo export dpkg_name=${name}
    echo export dpkg_version=${vers}
    echo export dpkg_arch=${arch}
    echo export dpkg_maintainer=\"${maint}\"
    echo export dpkg_short_description=\"${desc}\"
    echo export dpkg_section=${section}
    echo export dpkg_depends=\"${depends}\"
    echo export dpkg_buildrequires=\"${buildrequires}\"
    echo export dpkg_flags=\"${flags}\"
    echo export dpkg_subpackages=\"${subpackages}\"
    echo export dpkg_variants=\"${variants}\"
}

# Emit a deb control file on stdout
#  Usage: make_control [-d]
make_control()
{
    local pkg name vers arch maint desc section 
    local depends provides conflicts mname mvers

    name=$(get_pkg_name $*) || return 1
    vers=$(get_pkg_version $*) || return 1
    arch=$(get_pkg_arch) || return 1
    maint=$(get_pkg_var_req PKG_MAINTAINER) || return 1
    desc=$(get_pkg_var_req PKG_SHORT_DESCRIPTION) || return 1
    section=$(get_pkg_var_req PKG_SECTION) || return 1

    if [ $# = 1 ] && [ $1 = "-d" ]; then
        mname=$(get_pkg_name) || return 1
        mvers=$(get_pkg_version) || return 1
        depends="${mname} (= ${mvers})"
    else
        depends=$(get_pkg_var PKG_DEPENDS)
        provides=$(get_pkg_var PKG_PROVIDES)
        conflicts=$(get_pkg_var PKG_CONFLICTS)
    fi
    if get_pkg_opt variantsconflict; then
        for pkg in $(list_variants); do
            if [ ${pkg} != ${variant} ]; then
                conflicts=${conflicts}${conflicts:+,}${pkg}
            fi
        done
    fi

    echo Package: ${name}
    echo Version: ${vers}
    echo Architecture: ${arch}
    echo Maintainer: ${maint}
    echo Description: ${desc}
    echo Section: ${section}
    if [ -n "${depends}" ]; then 
        echo Depends: ${depends}
    fi
    if [ -n "${provides}" ]; then 
        echo Provides: ${provides}
    fi
    if [ -n "${conflicts}" ]; then 
        echo Conflicts: ${conflicts}
    fi
}

# Emit build info file on stdout
#  Usage: make_buildinfo
make_buildinfo ()
{
    echo "Source: ${buildsrc}"
    echo "Date: $(date)"
    echo "Hostname: $(hostname)"
}

# Helper for make_dk()
#  Usage: find_libdirs tmproot libdir
find_libdirs ()
{
    local file

    # note: trailing / needed for libdir that is a symlink
    # note: path is relative to tmproot so we chop off leading ./ in result
    # FIXME need to handle arches with different archive suffix
    pushd $1 >/dev/null || die "cannot chdir to $1"
      for file in $(find .$2/ -name \*.so\* 2>/dev/null | sed -e 's/^\.//'); do
        dirname ${file}
      done | sort | uniq
    popd >/dev/null
}

# Create a dotkit for this package on stdout.
#  Usage make_dk [-d]
make_dk ()
{
    local pfx name ver root tmpstr bname

    pfx=$(get_pkg_prefix $*) || return 1
    name=$(get_pkg_name $*) || return 1
    ver=$(get_pkg_version $*) || return 1
    root=$(get_tmproot $*)

    get_pkg_opt nodk && return 0

    if get_pkg_opt dkhide \
      || ( [ "$1" = "-d" ]  && get_pkg_opt dkhidedefault ) \
      || ( [ "$1" != "-d" ] && get_pkg_opt dkhidemain ); then
        echo "#a"
    fi
    if tmpstr=$(get_pkg_var PKG_DK_CATEGORY); then
        echo '#c' "${tmpstr}"
    elif tmpstr=$(get_pkg_var PKG_CATEGORY); then
        warn "PKG_CATEGORY is deprecated, use PKG_DK_CATEGORY"
        echo '#c' "${tmpstr}"
    elif tmpstr=$(get_pkg_var_req PKG_SECTION); then
        echo '#c' local-${tmpstr}
    else
        return 1
    fi

    tmpstr=$(get_pkg_var_req PKG_SHORT_DESCRIPTION) || return 1
    echo '#d' "${tmpstr}"

    if tmpstr=$(get_pkg_var_withmacros PKG_DK_HELP); then
        echo -e "${tmpstr}" | sed 's/^/#h /'
    elif tmpstr=$(get_pkg_var_withmacros PKG_HELP); then
        warn "PKG_HELP is deprecated, use PKG_DK_HELP"
        echo -e "${tmpstr}" | sed 's/^/#h /'
    fi

    # unuse all other forms of the package if dkmutex
    if get_pkg_opt dkmutex; then
        bname=$(get_pkg_basename) || return 1
        echo "unuse -q \`dk_rep '${bname}-[0-9]*'\` ${bname}"
    fi

    # load dotkits of dependent packages unles decoupledk
    if ! get_pkg_opt decoupledk; then
        for tmpstr in $(list_depends); do 
            echo "dk_op -q ${tmpstr}"; 
        done
    fi

    if [ -d ${root}${pfx}/bin ] || [ -h ${root}${pfx}/bin ]; then
        echo "dk_alter PATH ${pfx}/bin"
    fi
    if [ -d ${root}${pfx}/info ] || [ -h ${root}${pfx}/info ]; then
        echo "dk_alter INFOPATH ${pfx}/info"
    fi
    if [ -d ${root}${pfx}/man ] || [ -h ${root}${pfx}/man ]; then
        echo "dk_alter MANPATH ${pfx}/man"
    fi

    if ! get_pkg_opt noldpath; then
        for tmpstr in $(find_libdirs ${root} ${pfx}/lib); do
            echo "dk_alter LD_LIBRARY_PATH ${tmpstr}"
        done
    fi

    echo "dpkg-logger -p ${name} -d pid=\$\$ op=\$_dk_op"
}

# Validate that files referenced in 'doc' file actually exist
#  Usage: check_doc
check_doc()
{
    local file
    local result=0

    if [ -f ${tmproot}/DEBIAN/doc ]; then
        if [ $(wc -l < ${tmproot}/DEBIAN/doc) != $(grep : ${tmproot}/DEBIAN/doc | wc -l) ]; then
            warn "check_doc: malformed doc entry"
            return 1
        fi
        for file in $(sed -e 's/^[^:]*:[ \t]*//' ${tmproot}/DEBIAN/doc); do
            if ! [ -f ${tmproot}${file} ] && ! [ -h ${tmproot}${file} ]; then 
                warn "check_doc: no such file: ${tmproot}${file}"
                result=1 # keep going to warn of all missing files
            fi
        done
    fi
    return ${result}
}

# Emit md5sumps for all package files to stdout
#  Usage: make_md5sums [-d]
make_md5sums()
{
    local root=$(get_tmproot $*)

    # FIXME: use ${dpkgroot} instead of hard coded directory
    pushd ${root} >/dev/null || return 1
        if ! [ -d usr/local ]; then
             warn "${root}/usr/local does not exist!"
             return 1
        fi
        find usr/local -type f -exec md5sum {} \; # skips symlinks
    popd >/dev/null
}

make_linkdata2()
{
    local root=$(get_tmproot $*)
    local file

    which base64 >/dev/null || die "base64 is missing"

    # FIXME: use ${dpkgroot} instead of hard coded directory
    pushd ${root} >/dev/null || return 1
        if ! [ -d usr/local ]; then
             warn "${root}/usr/local does not exist!"
             return 1
        fi
        find usr/local -type l | while read file; do  # only symlinks
            echo "$(readlink -n "${file}" | base64 -w 0) ${file}"
        done
    popd >/dev/null
}

# Append stdin to tmpout (create it if necessary).
# Also cc stdout if -v option.
logappend ()
{
    if [ $vopt = 0 ]; then
        cat >>${tmpout}
    else
        tee -a ${tmpout} >&2
    fi
}

# Create wrapper scripts listed in PKG_WRAPPERS.
#  Usage create_wrappers [-d]
create_wrappers ()
{
    local root ext name lbindir bindir lmandir mandir wrappers basever wrap sec

    if wrappers=$(get_pkg_var PKG_WRAPPERS); then
        sec=$(get_pkg_var_req PKG_SECTION) || return 1
        if [ ${sec} = "root" ]; then
            warn "cannot use PKG_WRAPPERS with PKG_SECTION=root"
            return 1
        fi
        name=$(get_pkg_name $*) || return 1
        pfx=$(get_pkg_prefix $*) || return 1
        root=$(get_tmproot $*)

        lbindir=${root}${dpkgroot}/bin
        bindir=${root}${pfx}/bin
        lmandir=${root}${dpkgroot}/man
        mandir=${root}${pfx}/man

        # construct hyphenated extension if no -d
        if [ $# = 0 ]; then
            basever=$(get_pkg_basever) || return 1
            if get_pkg_opt nodashwrap; then
                ext=${basever:+"${basever}"}
            else
                ext=${basever:+"-${basever}"}
            fi
        fi

        mkdir -p ${lbindir} || return 1
        mkdir -p ${lmandir}/man1 || return 1

        # create wrappers and their man pages
        for wrap in $(split ${wrappers}); do
            if ! get_pkg_opt nocheckwrap && ! [ -x ${bindir}/${wrap} ]  \
                    && ! [ -h ${bindir}/${wrap} ] && ! [ -h ${bindir} ]; then
                warn "trying to wrap nonexistant executable: ${wrap}"
                return 1
            fi
            cat >${lbindir}/${wrap}${ext} <<EOT || return 1
#!/bin/bash --posix
exec /usr/bin/dpkg-wrap ${name} ${wrap} "\$@"
EOT
            chmod 555 ${lbindir}/${wrap}${ext} || return 1

            if   [ -f ${mandir}/man1/${wrap}.1 ] \
              || [ -h ${mandir}/man1/${wrap}.1 ] ; then
                ln -s ${pfx}/man/man1/${wrap}.1 ${lmandir}/man1/${wrap}${ext}.1
            elif [ -f ${mandir}/man1/${wrap}.1.gz ] \
              || [ -h ${mandir}/man1/${wrap}.1.gz ] ; then
                ln -s ${pfx}/man/man1/${wrap}.1.gz ${lmandir}/man1/${wrap}${ext}.1.gz
            fi
        done
    fi
}

# get source into tmpsrc
copy_tmpsrc ()
{
    local name=$(get_pkg_name)

    if [ -d ${buildsrc} ]; then
        warn "copying '${name}' source to tmpsrc"
        (echo "*** copy begin"; set -e; set -x; \
        rsync -av --exclude .svn ${buildsrc}/ ${tmpsrc}; \
            echo "*** copy status=$?") 2>&1 | logappend
        if ! grep -q "*** copy status=0" ${tmpout}; then
            [ ${vopt} = 1 ] || cat ${tmpout} >&2
            die "copy failed"
        fi
    else
        warn "exporting '${name}' to tmpsrc"
        (echo "*** export begin"; set -e; set -x; \
        svn --force export ${buildsrc} ${tmpsrc}; \
            echo "*** export status=$?") 2>&1 | logappend
        if ! grep -q "*** export status=0" ${tmpout}; then
            [ ${vopt} = 1 ] || cat ${tmpout} >&2
            die "export failed"
        fi
    fi
}

#############################################################################
# main package
#############################################################################

# Install buildrequires into 'tmplocal'
install_buildrequires ()
{
    local pkg deps
    local ret=0

    if deps=$(get_pkg_var PKG_BUILDREQUIRES); then
        if ! apt-userinst $(split ${deps}); then
            warn "apt-userinst failed"
            return 1
        fi
        for pkg in $(split ${deps}); do
            if ! checkreq ${pkg}; then
                warn "package ${pkg} is not installed" 
                ret=1
            fi
        done
    fi
    [ "${ret}" = 1 ] && warn "package build requirements were not met"
    return ${ret}
}

# Remove buildrequires from 'tmplocal'
remove_buildrequires ()
{
    if [ -d ${dpkgroot}/dpkg-db ]; then
        if ! dpkg -r --force-not-root $(dpkg-query -W -f='${Package}\n'); then
            warn "failed to remove all PKG_BUILDREQUIRES packages from image"
            return 1
        fi
        rm -rf ${dpkgroot}/dpkg-db
    fi
    return 0
}

# Use (in the dotkit sense) all the packages needed to build this package
# Helper for main_package_build().
use_buildreqs ()
{
    local pkg deps

    if deps=$(get_pkg_var PKG_BUILDREQUIRES); then
        unset DK_ROOT
        unset DK_NODE
        unset DK_SUBNODE
        unset _dk_inuse
        eval $(${dkinit})

        for pkg in $(split ${deps}); do
            pkg=$(echo -n ${pkg} | cut -d= -f1) # drop [=version]
            [ -e ${dpkg_infodir}/${pkg}.dk ] && use -q ${pkg}
        done
    fi
}

# Execute package.conf::pkg_build() in a subshell environment.
main_package_build ()
{
    local name=$(get_pkg_name)

    if [ $uopt = 1 ]; then
        warn "installing packages required for build in private /usr/local"
        (install_buildrequires; \
            echo "*** install_buildrequires status=$?" ) 2>&1 | logappend
        if ! grep -q "*** install_buildrequires status=0" ${tmpout}; then
            [ ${vopt} = 1 ] || cat ${tmpout} >&2
            die "failed to install buildrequires packages"
        fi
    fi
    warn "building '${name}' in tmpsrc"
    (cd ${tmpsrc}; set_meta; use_buildreqs; set_macros; source ${pkgconf}; \
        echo "*** pkg_build begin"; \
        set -e; set -x; pkg_build ${tmproot}; \
            echo "*** pkg_build status=$?") 2>&1 | logappend
    if ! grep -q "*** pkg_build status=0" ${tmpout}; then
        [ ${vopt} = 1 ] || cat ${tmpout} >&2
        die "pkg_build script failed"
    fi
}

# Convert /usr/local sandbox into a tmproot-like thing.
# Helper for main_package_install().
#  Usage: convert_root /usr/local
convert_root()
{
    local newroot ldir file

    newroot=$(mktemp -d $1/tmp.XXXXXXXXXX) || die "mktemp failed"
    ldir=${newroot}$1

    mkdir -p ${ldir} || die "could not mkdir ${ldir}"
    pushd $1 >/dev/null || die "could not chdir to $1"
        for file in $(/bin/ls -a1 .); do
            case ${file} in
                .|..|$(basename ${newroot}) ) ;;
                *) mv ${file} ${ldir} || die "mv ${file} ${ldir} failed" ;;
            esac
        done
    popd >/dev/null
    echo ${newroot}
}

# Execute package.conf::pkg_install() in a subshell environment.
main_package_install ()
{
    local name=$(get_pkg_name)
    local n

    mkdir -p ${tmproot} || die "mkdir ${tmproot} failed"
    if get_pkg_opt notmproot; then
        savedtmproot=${tmproot}
        tmproot=/
        warn "installing '${name}' to private /usr/local"
    else
        warn "installing '${name}' to tmproot"
    fi
    (cd ${tmpsrc}; set_meta; use_buildreqs; set_macros; source ${pkgconf}; \
        echo "*** pkg_install begin"; \
        mkdir -p ${tmproot}${dpkgroot}
        set -e; set -x; pkg_install ${tmproot}; \
            echo "*** pkg_install status=$?") 2>&1 | logappend
    if ! grep -q "*** pkg_install status=0" ${tmpout}; then
        [ ${vopt} = 1 ] || cat ${tmpout} >&2
        die "pkg_install script failed"
    fi
    if get_pkg_opt notmproot; then
        warn "removing packages required for build from private /usr/local"
        (remove_buildrequires; \
            echo "*** remove_buildrequires status=$?" ) 2>&1 | logappend
        if ! grep -q "*** remove_buildrequires status=0" ${tmpout}; then
            [ ${vopt} = 1 ] || cat ${tmpout} >&2
            die "failed to remove buildrequires packages"
        fi
        tmproot=$(convert_root ${dpkgroot})
    fi
    create_wrappers || die "failed to create wrappers"
    chmod -R go=u-w ${tmproot}
    find ${tmproot} -type d -exec chmod u+w {} \;
}

# If file has zero length, remove it.
# If file exists and has size greater than zero, chmod it.
#  Usage: check_mfile mode path
check_mfile ()
{
    local mode=$1
    local path=$2

    if [ -e ${path} ]; then
        if [ -s ${path} ]; then
            chmod ${mode} ${path}
        else
            rm -f ${path}
        fi
    fi
}

# Create metadata files under ${tmproot}/DEBIAN.
main_package_metadata ()
{
    warn "creating package metadata in tmproot"
    mkdir -p ${tmproot}/DEBIAN

    make_md5sums >${tmproot}/DEBIAN/md5sums || die "failed to make md5sums"
    check_mfile 444 ${tmproot}/DEBIAN/md5sums

    make_linkdata2 >${tmproot}/DEBIAN/linkdata2 || die "failed to make linkdata"
    check_mfile 444 ${tmproot}/DEBIAN/linkdata2

    make_control >${tmproot}/DEBIAN/control || die "failed to make control"
    check_mfile 444 ${tmproot}/DEBIAN/control

    make_buildinfo >${tmproot}/DEBIAN/buildinfo
    check_mfile 444 ${tmproot}/DEBIAN/buildinfo

    cat ${tmpout} >${tmproot}/DEBIAN/buildlog
    check_mfile 444 ${tmproot}/DEBIAN/buildlog

    if [ -r ${tmpsrc}/package.test ]; then
        cp ${tmpsrc}/package.test ${tmproot}/DEBIAN/test
        check_mfile 555 ${tmproot}/DEBIAN/test
    fi

    get_pkg_var_withmacros PKG_conffiles  >${tmproot}/DEBIAN/conffiles
    check_mfile 444 ${tmproot}/DEBIAN/conffiles

    get_pkg_var_withmacros PKG_doc  >${tmproot}/DEBIAN/doc
    check_mfile 444 ${tmproot}/DEBIAN/doc
    check_doc || die "doc check failed"

    (get_pkg_var_withmacros PKG_dk || make_dk) >${tmproot}/DEBIAN/dk \
        || die "failed to create dotkit"
    check_mfile 444 ${tmproot}/DEBIAN/dk
    
    make_macros >${tmproot}/DEBIAN/macros || die "failed to make macros"
    check_mfile 444 ${tmproot}/DEBIAN/macros
}

#############################################################################
# default package
#############################################################################

dflt_lcc_symlinks ()
{
    local name=$(get_pkg_name) || return 1
    local name2=$(get_pkg_name -d) || return 1
    local lccdir=${dpkgroot}/etc/lcc
    local file file2

    # Example:
    #  mvapich-gcc::c.lcc   -> mvapich-gcc-0.9.9::c.lcc
    #  mvapich-gcc::cxx.lcc -> mvapich-gcc-0.9.9::cxx.lcc

    shopt -s nullglob
    for file in ${tmproot}${lccdir}/${name}*.lcc; do
        file=$(basename ${file})
        file2=$(echo ${file} | sed -e "s/${name}/${name2}/")
        mkdir -p ${tmproot2}${lccdir} || return 1
        ln -s ${lccdir}/${file} ${tmproot2}${lccdir}/${file2} || return 1
    done
    shopt -u nullglob
    return 0
}

# Build default package
dflt_package_install ()
{
    local pfx=$(get_pkg_prefix) || exit 1
    local pfx2=$(get_pkg_prefix -d) || exit 1

    mkdir -p ${tmproot2}${dpkgroot} || die "mkdir failed"
    if [ -d ${tmproot}${pfx} ]; then
        mkdir -p $(dirname ${tmproot2}${pfx2}) || die "mkdir failed"
        dpkg-lndir ${tmproot} ${pfx} ${tmproot2} ${pfx2} || die "dpkg-lndir failed"
        create_wrappers -d || die "failed to create wrappers"
    fi
    dflt_lcc_symlinks || exit 1
    chmod -R go=u-w ${tmproot2}
    find ${tmproot2} -type d -exec chmod u+w {} \;

    return 0
}

# Create metadata for default package
dflt_package_metadata ()
{
    mkdir -p ${tmproot2}/DEBIAN

    make_md5sums -d >${tmproot2}/DEBIAN/md5sums || die "failed to make md5sums"
    check_mfile 444 ${tmproot2}/DEBIAN/md5sums

    make_linkdata2 -d >${tmproot2}/DEBIAN/linkdata2 || die "failed to make linkdata"
    check_mfile 444 ${tmproot2}/DEBIAN/linkdata2

    make_control -d >${tmproot2}/DEBIAN/control || die "failed to make control"
    check_mfile 444 ${tmproot2}/DEBIAN/control

    make_buildinfo  >${tmproot2}/DEBIAN/buildinfo
    check_mfile 444 ${tmproot2}/DEBIAN/buildinfo

    if [ -r ${tmpsrc}/package.test ]; then
        cp ${tmpsrc}/package.test ${tmproot2}/DEBIAN/test
        check_mfile 555 ${tmproot2}/DEBIAN/test
    fi

    (get_pkg_var_withmacros -d PKG_dk || make_dk -d) >${tmproot2}/DEBIAN/dk \
        || die "failed to create dotkit"
    check_mfile 444 ${tmproot2}/DEBIAN/dk

    make_macros -d >${tmproot2}/DEBIAN/macros || die "failed to make macros"
    check_mfile 444 ${tmproot2}/DEBIAN/macros
}

#############################################################################
# initialization
#############################################################################

init_buildsrc ()
{
    buildsrc=$1
    if [ -d ${buildsrc} ]; then
        buildsrc=$(fullpath ${buildsrc})
    elif echo ${buildsrc} | grep -q /tags/; then
        snapshot=""
    fi    
}

# Locate and quickly check the package.conf.
init_check_pkgconf ()
{
    if [ -n "${popt}" ]; then
        cp ${popt} ${pkgconf} || die "package.conf copy failed"
        [ -n "${mopt}" ] && cp ${mopt} ${buddha} 2>/dev/null # ignore errors
    elif [ -d ${buildsrc} ]; then
        cp ${buildsrc}/package.conf ${pkgconf} || die "package.conf copy failed"
        cp ${buildsrc}/META ${buddha} 2>/dev/null # ignore errors
    else
        svn cat ${buildsrc}/package.conf >${pkgconf} || die "svn cat failed"
        svn cat ${buildsrc}/META 2>/dev/null >${buddha} # ignore errors
    fi
    # check for parse errors
    (set -e; source ${pkgconf}) || die "bash error sourcing package.conf"

    # check for missing variables
    get_pkg_var_req PKG_NAME >/dev/null || clean_exit 1
    get_pkg_var_req PKG_VERSION >/dev/null || clean_exit 1
    get_pkg_var_req PKG_MAINTAINER >/dev/null || clean_exit 1
    get_pkg_var_req PKG_SHORT_DESCRIPTION >/dev/null || clean_exit 1
    get_pkg_var_req PKG_SECTION >/dev/null || clean_exit 1
}

# Verify that PKG_FLAGS contains valid information
init_check_flags ()
{
    local flags opt
    local result=0

    flags=$(get_pkg_var PKG_FLAGS) || return 0

    for opt in $(split ${flags}); do
        case ${opt} in
            variantsconflict|notmproot) ;;              # misc
            dkmutex|nodk|decoupledk|noldpath) ;;        # dotkit related
            dkhide|dkhidemain|dkhidedefault) ;;         #  (continued)
            verboselog|nocheckwrap|nodashwrap) ;;       # wrapper related
            *)  warn "unknown flag: ${opt}"; result=1 ;;
        esac
    done
    [ ${result} = 1 ] && die "PKG_FLAGS contains unknown flags"
}

# Check that available subpackages match usage of -s option.
init_check_subpackage ()
{
    local name subs

    subs=$(get_pkg_var PKG_SUBPACKAGES) # ignore error

    echo ${subs} | grep -q "_" && die "``_'' is illegal in subpackage name"
    if [ -n "${subs}" ]; then
        for name in $(split ${subs}); do
            [ "${name}" = "${subpackage}" ] && return 0
        done
        die "specify a valid subpackage with -s: ${subs}"
    else 
        [ -n "${subpackage}" ] && die "this package has no subpackages"
    fi
    return 0
}

# Check that available variants match usage of -V option.
init_check_variant ()
{
    local name vars

    vars=$(list_variants) # ignore error

    echo ${vars} | grep -q "_" && die "``_'' is illegal in variant name"
    if [ -n "${vars}" ]; then
        for name in ${vars}; do
            [ "${name}" = "${variant}" ] && return 0
        done
        die "specify a valid variant with -V: " ${vars}
    else 
        [ -n "${variant}" ] && die "this package has no variants"
    fi
    return 0
}

# Look for problems with default package config
init_check_dflt ()
{
    local dflt name tmpstr sec

    if dflt=$(get_pkg_var PKG_DEFAULT); then
        sec=$(get_pkg_var_req PKG_SECTION) || clean_exit 1
        [ ${sec} != root ] || die "PKG_SECTION=root won't work with PKG_DEFAULT"
        name=$(get_pkg_var_req PKG_NAME) || clean_exit 1
        [ ${name} != "${dflt}" ] || die "PKG_NAME and PKG_DEFAULT are identical"
        tmpstr=$(get_pkg_basename) || clean_exit 1
        if [ "${dflt}" != ${tmpstr} ]; then
            die "PKG_DEFAULT=${dflt} != de-versioned PKG_NAME=${tmpstr}"
        fi
    fi
}

# Validate that the packages needed to build this package are installed
init_check_buildrequires ()
{
    local pkg deps
    local ret=0

    if [ ${topt} = 1 ] && ! get_pkg_opt notmproot; then
        if deps=$(get_pkg_var PKG_BUILDREQUIRES); then
            for pkg in $(split ${deps}); do
                if ! checkreq ${pkg}; then
                    warn "package ${pkg} is not installed" 
                    ret=1
                fi
            done
        fi
    fi
    [ "${ret}" = 1 ] && die "package build requirements were not met"
}

# Check if destination deb(s) exists and refuse to overwrite without -f option.
init_check_debfiles ()
{
    if [ -z "${outfile}" ]; then
        name=$(get_pkg_name) || clean_exit 1
        vers=$(get_pkg_version) || clean_exit 1
        arch=$(get_pkg_arch) || clean_exit 1
        outfile=${name}_${vers}_${arch}.deb
    fi
    if get_pkg_var PKG_DEFAULT >/dev/null && [ -z "${outfile2}" ]; then
        name=$(get_pkg_name -d) || clean_exit 1
        vers=$(get_pkg_version -d) || clean_exit 1
        arch=$(get_pkg_arch) || clean_exit 1
        outfile2=${name}_${vers}_${arch}.deb
    fi
    if [ -e ${outfile} ] && [ ${fopt} = 0 ]; then
        die "${outfile} already exists, force overwrite with -f"
    fi
    if [ -n "${outfile2}" ] && [ -e ${outfile2} ] && [ ${fopt} = 0 ]; then
        die "${outfile2} already exists, force overwrite with -f"
    fi
}

# Start dpkg-mkdeb over in a tmproot
init_restart_if_direct ()
{
    [ ${uopt} = 1 ] && return # avoid recursion

    if [ ${topt} = 0 ] || get_pkg_opt notmproot; then
        warn "restarting with private ${dpkgroot}"
        kopt=0  # don't keep the aborted workdir
        cleanup
        exec dpkg-tmplocal -- ${selfpath} -u ${argscpy}
        die "exec dpkg-tmplocal failed"
    fi
}

#############################################################################
# MAIN
#############################################################################

usage ()
{
    echo "Usage: ${prog} [-fvkt] [-p conf] [-s subpkg] [-V variant] [svnurl | srcdir]" >&2
    echo "   or: ${prog} -q query-list"
    clean_exit 1
}

[ $(id -u) != 0 ] || die "you must not build packages as superuser"

umask 022

# initialize environment
PATH=/bin:/usr/bin:/usr/sbin:/sbin:${dpkgroot}/bin
unset LD_LIBRARY_PATH
unset DK_ROOT
unset DK_NODE
unset DK_SUBNODE
unset _dk_inuse
unset OPTIND

argscpy="$@"
while getopts "?m:hup:fvV:q:kts:o:O:x:S" opt; do
    case ${opt} in
        h|\?) usage ;;
        p) popt=${OPTARG} ;;        # select non-default package.conf
        m) mopt=${OPTARG} ;;        # select non-default META
        s) subpackage=${OPTARG} ;;  # select subpackage
        V) variant=${OPTARG} ;;     # select variant
        q) query=${OPTARG} ;;       # query information from package.conf
        f) fopt=1 ;;                # force even if deb exists
        u) uopt=1 ;;                # restarted as direct install (secret arg)
        v) vopt=1 ;;                # set verbose mode
        k) kopt=1 ;;                # set "keep build dir" mode
        t) topt=1 ;;                # don't use tmplocal unless notmproot
        o) outfile=${OPTARG} ;;     # [testing] set path for main deb
        O) outfile2=${OPTARG} ;;    # [testing] set path for dflt deb
        x) selfpath=${OPTARG} ;;    # [testing] set path for recursion
        S) snapshot="" ;;           # [testing] disable snapshot
        *) die "bad option: ${opt}" ;;
    esac
done
shift $((${OPTIND} - 1))
[ $# = 1 ] || usage
[ -n "${mopt}" ] && ! [ -n "${popt}" ] && die "-m requires -p"

# initialization
init_buildsrc $1
init_check_pkgconf

if [ -n "${query}" ]; then
    query_vars $(split ${query})
    clean_exit 0
fi

# more initialization
init_check_subpackage
init_check_flags
init_check_variant
init_check_dflt
init_check_buildrequires
init_check_debfiles
init_restart_if_direct

copy_tmpsrc

# build main package
main_package_build
main_package_install
main_package_metadata
dpkg-deb --build ${tmproot} ${outfile} || die "dpkg-deb failed"

# build default package
if get_pkg_var PKG_DEFAULT >/dev/null; then
    dflt_package_install
    dflt_package_metadata
    dpkg-deb --build ${tmproot2} ${outfile2} || die "dpkg-deb failed"
fi

# preserve tmproot
if [ ${kopt} = 1 ] && get_pkg_opt notmproot; then
    rsync -av ${tmproot}/ ${savedtmproot} >/dev/null \
                || die "failed to back up tmproot"
fi

clean_exit 0
# vi: expandtab sw=4 ts=4
