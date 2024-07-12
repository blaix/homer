#!/usr/bin/env bash

# Borrowed from lydell:
# https://github.com/lydell/dotfiles/blob/master/.git-templates/hooks/pre-commit

keyword='NOCOMMIT'
additions="$(git diff --staged --diff-filter=ACM | grep '^+')"

if echo "$additions" | grep --quiet "$keyword"; then
  echo "Error: $keyword found in added lines!"
  # Print file names with offending lines, and the offending lines.
  echo "$additions" \
    | grep "$keyword\|^+++" \
    | grep --before-context=1 --color=always "$keyword"
  exit 1
fi
