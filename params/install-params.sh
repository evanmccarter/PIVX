#!/usr/bin/env bash
#
# Copyright (c) 2015-2020 The Zcash developers
# Copyright (c) 2020-2021 The PIVX Core developers
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.

export LC_ALL=C.UTF-8

set -eu

if [ -n "${1:-}" ]; then
    PARAMS_DIR="$1"
else
    if [[ "$OSTYPE" == "darwin"* ]]; then
        PARAMS_DIR="$HOME/Library/Application Support/PIVXParams"
    else
        PARAMS_DIR="$HOME/.pivx-params"
    fi
fi

SAPLING_SPEND_NAME='sapling-spend.params'
SAPLING_OUTPUT_NAME='sapling-output.params'

SHA256CMD="$(command -v sha256sum || echo shasum)"
: "${SHA256CMD}"
SHA256ARGS="$(command -v sha256sum >/dev/null || echo '-a 256')"
: "${SHA256ARGS}"

pushd () {
    command pushd "$@" > /dev/null
}

popd () {
    command popd > /dev/null
}

function install_params {
    local filename="$1"
    local output="$2"
    local expectedhash="$3"

    # if the params don't exist in the current directory, assume we're running from release tarballs
    if ! [ -f "$filename" ]
    then
        filename="share/pivx/$filename"
    fi

    if ! [ -f "$output" ]
    then
        if
            command -v sha256sum >/dev/null
        then
            command sha256sum -c <<EOF
$expectedhash  $filename
EOF
        else
            shasum -a 256 -c <<EOF
$expectedhash  $filename
EOF
        fi

        # Check the exit code of the shasum command:
        CHECKSUM_RESULT=$?
        if [ $CHECKSUM_RESULT -eq 0 ]; then
            cp -v "$filename" "$output"
        else
            echo "Failed to verify parameter checksums!" >&2
            exit 1
        fi
    fi
}

function exit_locked_error {
    echo "Only one instance of install-params.sh can be run at a time." >&2
    exit 1
}

function main() {

    # Use flock to prevent parallel execution.
    if [[ "$OSTYPE" == "darwin"* ]]; then
        shlock -f /tmp/install_params.lock -p $$
    else
        # create lock file
        eval "exec 200>/tmp/install_params.lock"
        # acquire the lock
        flock -n 200
    fi \
    || exit_locked_error

    cat <<EOF
PIVX - install-params.sh

This script will install the PIVX zkSNARK parameters and verify their
integrity with sha256sum.

If they already exist locally, it will exit now and do nothing else.
EOF

    # Now create PARAMS_DIR and insert a README if necessary:
    if ! [ -d "$PARAMS_DIR" ]
    then
        mkdir -p "$PARAMS_DIR"
        README_PATH="$PARAMS_DIR/README"
        cat >> "$README_PATH" <<EOF
This directory stores common PIVX zkSNARK parameters. Note that it is
distinct from the daemon's -datadir argument because the parameters are
large and may be shared across multiple distinct -datadir's such as when
setting up test networks.
EOF

        # This may be the first time the user's run this script, so give
        # them some info:
        cat <<EOF
If the files are already present and have the correct
sha256sum, nothing else is done.

Creating params directory. For details about this directory, see:
$README_PATH

EOF
    fi

    if [ -d ".git" ] || [ -f autogen.sh ]
    then
        echo "Installing from source repo or dist tarball"
        pushd params
    fi

    # Sapling parameters:
    install_params "$SAPLING_SPEND_NAME" "$PARAMS_DIR/$SAPLING_SPEND_NAME" "8e48ffd23abb3a5fd9c5589204f32d9c31285a04b78096ba40a79b75677efc13"
    install_params "$SAPLING_OUTPUT_NAME" "$PARAMS_DIR/$SAPLING_OUTPUT_NAME" "2f0ebbcbb9bb0bcffe95a397e7eba89c29eb4dde6191c339db88570e3f3fb0e4"

    if [ -d ".git" ] || [ -f autogen.sh ]
    then
        popd
    fi
}

main
rm -f /tmp/install_params.lock
exit 0
