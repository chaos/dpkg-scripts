#!/bin/bash --posix

declare -r prog=dpkg-defaults

extract_dflt ()
{
    echo $1 | sed -e 's/_default-/-/' | sed -e 's/-[^-]*$//'
}

extract_base ()
{
    echo $1 | sed -e 's/_.*//'
}

usage ()
{
    echo "Usage: ${prog} [default-name]"
    exit 1
}

while getopts "?h" opt; do
    case ${opt} in
        h|\?) usage ;;
        *) die "bad option: ${opt}" ;;
    esac
done
shift $((${OPTIND} - 1))

for i in $(dpkg-query -Wf '${Package}_${Version}\n' $* | grep _default-); do
    dflt=$(extract_dflt $i)
    base=$(extract_base $i)
    echo "${base}:"
    for opt in $(dpkg-query -Wf '${Package}\n' "${base}-[0-9]*"); do
        [ "${opt}" = "${base}" ] && continue
        if [ "${opt}" = "${dflt}" ]; then
            echo "  *${opt}"
        else
            echo "   ${opt}"
        fi
    done
done
