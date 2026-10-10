#!/bin/sh
# Builds dist/balatro-sidebar-<version>.zip from the committed files.
set -e
cd "$(dirname "$0")"
version=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' sidebar.json)
mkdir -p dist
git archive --prefix=balatro_sidebar/ -o "dist/balatro-sidebar-$version.zip" HEAD \
    sidebar.lua sidebar.json README.md LICENSE
echo "dist/balatro-sidebar-$version.zip"
