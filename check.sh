#!/usr/bin/env bash

# Copyright (c) 2019, Peter Mrekaj. All rights reserved.
# Use of this source code is governed by a ISC-style
# license that can be found: https://opensource.org/licenses/ISC.

# This script helps maintain best practices.
# Add the following line into the .git/hooks/pre-commit:
# `bash -eo pipefail check.sh code_quality`
# Add the following line into the.git/hooks/post-commit:
# `bash -eo pipefail check.sh commit_message`
#
# The `commit_message` task checks the following on commit message:
# - the first line of the commit message hax maximum of 50 characters
# - the first line of the commit message matches the reqular expression
# - the second line of the commit message is empty
#
# The `code_quality` task checks the following on files prepared for commit:
# - all files are trailing whitespace free
# - all file names are in ASCII
# - all .go files have valid syntax
# - all .go files are formatted
# - all .go files are free from vet issues
# - all .go files are free from lint issues

function print() {
    printf "%-70s" "${1}"
}

function pass() {
    printf "OK\\n"
}

function fail() {
    printf "ERROR\\n%s\\n" "${1}"
    exit 1
}

 # A git tree which will be examine.
if git rev-parse --verify HEAD &>/dev/null; then
    readonly TREE=HEAD
else
    readonly TREE="$(git hash-object -t tree /dev/null)"
fi

readonly TASK="${1}"

case "${TASK}" in
    commit_message)
        print "Executing commit message check ..."
        readonly COMMIT_MSG=$(git log --format=%B -n 1 "${TREE}")
        readonly COMMIT_MSG_MAX_CHARS=50
        readonly COMMIT_MSG_REGEXP='^(fix|feat|refactor|test|docs|perf|style|chore)(\(.{2,20}\):|:) .*[^.\ ]$'
        if [[ "$(printf "%s" "${COMMIT_MSG}" | sed '1q;d' | wc -c)" -gt 50 ]]; then
            fail "Commit message \"${COMMIT_MSG}\" must have maximum of ${COMMIT_MSG_MAX_CHARS} characters"
        fi
        if printf "%s" "${COMMIT_MSG}" | sed '1q;d' | grep --quiet --invert-match --extended-regexp "${COMMIT_MSG_REGEXP}"; then
            fail "Commit message \"${COMMIT_MSG}\" must match: ${COMMIT_MSG_REGEXP}"
        fi
        if printf "%s" "${COMMIT_MSG}" | sed '2q;d' | grep --quiet --invert-match '^$'; then
            fail "Commit message \"${COMMIT_MSG}\" must have empty second line"
        fi
        pass
        ;;

    code_quality)
        readonly FILES="$(git diff --cached --name-only -z --diff-filter=d "${TREE}" | LC_ALL=C tr '\0' '\n')"
        [[ -z "${FILES}" ]] && exit 0
        printf "Files which will be examined:\\n%s\\n\\n" "${FILES}"

        print "Executing no trailing whitespaces check on all files ..."
        readonly TW=$(git diff-index --cached --check --diff-filter=d "${TREE}")
        [[ -n "${TW}" ]] && fail "$(printf "Affected files:\\n%s" "${TW}")"
        pass

        print "Executing non ASCII filenames check on all files ..."
        for file in ${FILES}; do
            if [[ "$(printf "%s" "${file}" | LC_ALL=C tr -d '[ -~]\0' | wc -c)" -ne 0 ]]; then
                NA=$(printf "%s\\n%s" "${NA}" "${file}")
            fi
        done
        [[ -n "${NA}" ]] && fail "$(printf "Affected files: %s" "${NA}")"
        pass

        # .go files which will be examined.
        readonly GO_FILES="$(printf "%s" "${FILES}" | grep '.go$')"

        if [[ -n "${GO_FILES}" ]]; then
            print "Executing valid syntax check on all .go files ..."
            for file in ${GO_FILES}; do
                IS=$(printf "%s\\n%s" "${IS}" "$( (gofmt -e "${file}" 1>/dev/null) 2>&1 )")
            done
            [[ -n "${IS}" ]] && fail "$(printf "Affected files: %s" "${IS}")"
            pass
        fi

        if [[ -n "${GO_FILES}" ]]; then
            print "Executing formatting and simplifications check on all .go files ..."
            for file in ${GO_FILES}; do
                FS=$(printf "%s\\n%s" "${FS}" "$(gofmt -s -l "${file}" 2>&1)")
            done
            [[ -n "${FS}" ]] && fail "$(printf "Affected files: %s" "${FS}")"
            pass
        fi

        if [[ -n "${GO_FILES}" ]]; then
            print "Executing vet check on all .go files ..."
            for file in ${GO_FILES}; do
                DIRS+=("$(go list -f '{{.Dir}}' "${file}")")
            done
            readonly UNIQUE_DIRS=$(tr ' ' '\n' <<< "${DIRS[@]}" | sort -u)
            for dir in ${UNIQUE_DIRS}; do
                VV=$(printf "%s\\n%s" "${VV}" "$(go vet "${dir}" 2>&1 | \
                grep --invert-match --fixed-strings "exit status 1")")
            done
            [[ -n "${VV}" ]] && fail "$(printf "Affected files: %s" "${VV}")"
            pass
        fi

        if [[ -n "${GO_FILES}" ]]; then
            print "Executing linter check on all .go files ..."
            for file in ${GO_FILES}; do
                LV=$(printf "%s\\n%s" "${LV}" "$(golint "${file}" 2>&1)")
            done
            [[ -n "${LV}" ]] && fail "$(printf "Affected files: %s" "${LV}")"
            pass
        fi

        # .sh files which will be examined.
        readonly SH_FILES="$(printf "%s" "${FILES}" | grep '.sh$')"

        if [[ -n "${SH_FILES}" ]]; then
            print "Executing linter check on all .sh files ..."
            for file in ${SH_FILES}; do
                LV=$(printf "%s\\n%s" "${LV}" "$(shellcheck --format gcc "${file}" 2>&1)")
            done
            [[ -n "${LV}" ]] && fail "$(printf "Affected files: %s" "${LV}")"
            pass
        fi
        ;;

    *)
        printf "Error! Unknown TASK: \`%s\`\\n" "${TASK}"
        exit 1
esac