#!/bin/bash
# Copyright IBM Corp. 2026
# SPDX-License-Identifier: MIT

PREFIX="CALL ADAPTER INIT SCRIPTS:"
DIR=/opt/IBM/svgadapters/timsol/scripts

if [ -d "$DIR" ]; then
  cd "$DIR"
  for S in $(ls override-*.sh init-*.sh); do
    echo "$PREFIX $S"
    ./$S
  done
else
  echo "$PREFIX $DIR does not exist, skipping."
fi
