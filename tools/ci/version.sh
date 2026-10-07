#!/bin/sh
# The version name of a CI build: the tag for a v* tag, otherwise
# nightly-YYYYMMDD-<short sha>.
case "${GITHUB_REF:-}" in
refs/tags/*) echo "$GITHUB_REF_NAME" ;;
*) echo "nightly-$(date -u +%Y%m%d)-$(git rev-parse --short HEAD)" ;;
esac
