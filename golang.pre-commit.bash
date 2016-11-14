#!/usr/bin/env bash

# Copyright (c) 2016, Peter Mrekaj. All Rights Reserved.
#
# Licensed under the MIT License, <LICENSE or http://opensource.org/licenses/MIT>.
# This file may not be copied, modified, or distributed except according to those terms.
#
# Pre-commit hook for GIT repositories that contain Golang source code.
# To use this hook, copy this file to the .git/hooks in your repository root,
# rename it to "pre-commit", and grant it an execution permission.
#
# This pre-commit hook checks the following on files prepared for commit:
# - Are filenames in ASCII
# - Are there no trailing whitespaces
# - Is gofmt installed
# - Are .go files syntactically correct
# - Are .go files correctly formatted
# - Is go installed
# - Are .go files correctly vetted
# - Is golint installed
# - Are .go files correctly lintered
#
# Use `git commit --no-verify` to skip the pre-commit hook.

set -o posix

readonly red=$(tput setaf 1)
readonly green=$(tput setaf 2)
readonly none=$(tput sgr0)
readonly bold=$(tput bold)

readonly info="${bold}PRECOMMIT:${none}"
readonly success="${green}OK${none}"
readonly failure="${red}FAILED${none}"

exit_code=0

# An git tree to check, default is an empty tree.
tree=$(git hash-object -t tree /dev/null)
if git rev-parse --verify HEAD &> /dev/null; then
    tree=HEAD
fi

# Print given string with ${info} prefix into the stdout.
function info {
    printf "%s $1" "${info}"
}

# Print given string with ${info} prefix into the stderr.
function error {
     printf "%s $1" "${info}" >&2
}

# Check if $1 == $2, then print the check result and return 0.
# If $1 != $2, then print the check result, set the EXIT_CODE=1 and return it.
# If $3 == true && $1 != $2, then do the same as in $1 != $2 case, plus exit
# with EXIT_CODE.
function check {
    local _got=$1
    local _want=$2
    local _exit_on_failure=${3:-false}
    if [ "$_got" == "$_want" ]; then
        printf "%s\n" "${success}"
        return 0
    fi
    printf "%s\n" "${failure}"
    exit_code=1
    if [ "$_exit_on_failure" == true ]; then
        exit $exit_code
    fi
    return $exit_code
}

# Check if there are any files to examine.
if [ -z "$(git diff --cached --name-only --diff-filter=d $tree)" ]; then
    exit $exit_code
fi

info "Checking that filenames are in ASCII ... "
git diff --cached --name-only --diff-filter=d -z $tree | LC_ALL=C tr -d '[ -~]\0' | wc -c &> /dev/null
check $? 0

info "Checking for no trailing whitespaces ... "
git diff-index --check --cached --diff-filter=d $tree -- &> /dev/null
check $? 0

# Check if there are any .go files to examine.
readonly go_files=$(git diff --cached --name-only --diff-filter=d $tree | grep '.go$')
if [ -z "${go_files}" ]; then
    exit $exit_code
fi

info "Checking for gofmt ... "
command -v gofmt &> /dev/null
check $? 0 true

info "Checking that syntax is valid ... "
errors=$( { gofmt -e "$go_files"; } 2>&1 )
if ! check $? 0; then
    error "Fix the following syntax errors:\n${errors}\n"
    exit $exit_code
fi

info "Checking formatting ... "
readonly unformatted=$(gofmt -l "$go_files")
if ! check "$unformatted" ""; then
    error "To fix formatting run:\n"
    for file in $unformatted; do
        printf "gofmt -w %s/%s\n" "$PWD" "$file"
    done
fi

info "Checking for go vet ... "
command -v go &> /dev/null
check $? 0 true

info "Vetting ... "
readonly unvetted=$( { go tool vet "$go_files"; } 2>&1 )
if ! check "$unvetted" ""; then
    error "Fix the following vet issues:\n${unvetted}\n"
fi

info "Checking for golint ... "
command -v golint &> /dev/null
check $? 0 true

info "Lintering ... "
readonly unlintered=$( { golint "$go_files"; } 2>&1 )
if ! check "$unlintered" ""; then
    error "Fix the following lint issues:\n${unlintered}\n"
fi

exit $exit_code
