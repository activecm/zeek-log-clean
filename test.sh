#!/bin/bash

# change to directory this script is in, follwoing any symlinks
pushd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" > /dev/null

# export BATSLIB_TEMP_PRESERVE=1
# export BATSLIB_TEMP_PRESERVE_ON_FAILURE=1
test/bats-core/bin/bats test

# change back to original directory
popd > /dev/null