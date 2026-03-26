#!/bin/bash

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
