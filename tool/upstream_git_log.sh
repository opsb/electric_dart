#!/bin/bash

# Show commit messages from the Electric repository.
# Used to include the original commit messages from the Electric repo when the Dart client is updated.
# Example usage: tool/upstream_git_log.sh 123abc..HEAD

set -e

ELECTRIC_REPO='../electric'

pushd "$ELECTRIC_REPO"

COMMIT_FORMAT='%h - %s%n%ad - %an%nhttps://github.com/electric-sql/electric/commit/%h%n'

TZ=UTC0 git log --pretty=format:"$COMMIT_FORMAT" --date=iso-local "$@"