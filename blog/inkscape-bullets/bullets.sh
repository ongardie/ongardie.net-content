#!/bin/bash

# top-level bullet and space
bullet='<tspan style="fill:#3465a4;">●<\/tspan> '
bulletnext='<tspan style="fill:none;">●<\/tspan> '

# second-level bullet and space
dash=$bulletnext'<tspan style="fill:#3465a4;"> –<\/tspan> '
dashnext=$bulletnext'<tspan style="fill:none;"> –<\/tspan> '

# the last argument to this script is the filename read from
shift $(( $# - 1 ))
f=$1

sed -e "s/\\*  /$bullet/" \
    -e "s/\\\\  /$bulletnext/" \
    -e "s/   - /$dash/" \
    -e "s/   \\\\ /$dashnext/" \
    $f
