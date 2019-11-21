#!/bin/bash

# Copyright (c) Facebook, Inc. and its affiliates.
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# This shell script lints only the things that changed in the most recent change.


DOCOPTS="--pre-summary-newline --wrap-descriptions 88 --wrap-summaries 88 \
    --make-summary-multi-line"

set -e

usage () {
    cat <<EOF
Usage: $0

Autoformats (or checks) code so it conforms with ParlAI standards. By default,
runs black, flake8, and docformatter only on the changed files in the current branch.

Optional Arguments

  -a, --all          run on all files, not just changed ones.
  -b, --black        only run black.
  -c, --check        perform a check, but don't make any changes.
  -d, --doc          only run docformatter.
  -f, --flake8       only run flake8.
  -h, --help         print this help message and exit
  -i, --internal     run within parlai_internal
EOF
}

reroot() {
    # possibly rewrite all filenames if root is nonempty
    if [[ "$1" != "" ]]; then
        cat | xargs -I '{}' realpath --relative-to=. $1/'{}'
    else
        cat
    fi
}

onlyexists() {
    # filter filenames based on what exists on disk
    while read fn; do
        if [ -f "${fn}" ]; then
            echo "$fn"
        fi
    done
}

RUN_ALL_FILES=0
RUNALL=1
INTERNAL=0
CHECK=0
CMD=""
while true; do
  case $1 in
    -h | --help)
      usage
      exit 0
      ;;
    -a | --all)
      RUN_ALL_FILES=1
      ;;
    -f | --flake8)
      [[ "$CMD" != "" ]] && (echo "Don't mix args." && false);
      RUNALL=0
      CMD="flake8"
      ;;
    -c | --check)
      CHECK=1
      ;;
    -d | --doc)
      [[ "$CMD" != "" ]] && (echo "Don't mix args." && false);
      CMD="docformatter"
      RUNALL=0
      ;;
    -i | --internal)
      INTERNAL=1
      ;;
    -b | --black)
      [[ "$CMD" != "" ]] && (echo "Don't mix args." && false);
      CMD="black"
      RUNALL=0
      ;;
    "")
      break
      ;;
    *)
      usage
      echo
      echo "Cannot handle arg $1."
      exit 1
      ;;
  esac
  shift
done

if [[ $INTERNAL -eq 1 ]]; then
    ROOT="$(git -C ./parlai_internal/ rev-parse --show-toplevel)"
    REPO="-C ./parlai_internal"
else
    ROOT=""
    REPO=""
fi

if [[ $RUN_ALL_FILES -eq 1 ]]; then
    CHECK_FILES="$(git $REPO ls-files | grep '\.py$' | reroot $ROOT | onlyexists $ROOT | tr '\n' ' ')"
else
    CHECK_FILES="$(git $REPO diff --name-only master... | grep '\.py$' | reroot $ROOT | onlyexists | tr '\n' ' ')"
fi

if [[ $RUNALL -eq 1 ]]
then
    if [[ $CHECK -eq 1 ]]; then A="$A -c"; fi
    if [[ $INTERNAL -eq 1 ]]; then A="$A -i"; fi
    if [[ $RUN_ALL_FILES -eq 1 ]]; then A="$A -a"; fi
    echo "Black:"
    bash $0 --black $A
    echo "------------------------------------------------------------------------------"
    echo "Doc formatting:"
    bash $0 --doc $A
    echo "------------------------------------------------------------------------------"
    echo "Flake8:"
    bash $0 --flake8 $A
    exit 0
fi

echo "Checking files:"
echo $CHECK_FILES

if [ "$CHECK_FILES" != "" ]
then
    if [[ "$CMD" == "black" ]]
    then
        command -v black >/dev/null || \
            ( echo "Please run \`pip install black\` and rerun $0." && false )
        if [[ $CHECK -eq 0 ]]
        then
            black $CHECK_FILES
        else
            black --check $CHECK_FILES
        fi
    elif [[ "$CMD" == "docformatter" ]]
    then
        command -v docformatter > /dev/null || \
            ( echo "Please run \`pip install docformatter\` and rerun $0." && false )
        if [[ $CHECK -eq 0 ]]
        then
            docformatter -i $DOCOPTS $CHECK_FILES
        else
            echo "The following require doc formatting:"
            docformatter -c $DOCOPTS $CHECK_FILES
        fi
    elif [[ "$CMD" == "flake8" ]]
    then
        command -v flake8 >/dev/null || \
            ( echo "Please run \`pip install flake8\` and rerun $0." && false )

        # soft complaint on too-long-lines
        flake8 --select=E501 --show-source $CHECK_FILES
        # hard complaint on really long lines
        exec flake8 --max-line-length=127 --show-source $CHECK_FILES
    else
        echo "Don't know how to \`$CMD\`."
        false
    fi
fi
