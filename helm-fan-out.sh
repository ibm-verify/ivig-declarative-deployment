#!/usr/bin/env bash
# Based on https://github.com/helm/helm/issues/4680#issuecomment-1152289297
# helm-fan-out

if [ -z "$1" ]; then
    echo "Please provide an output directory"
    exit 1
fi

awk -vout="$1" -F": " '
  $0~/^# Source: / {
    file=out"/"$2;
    if (!(file in filemap)) {
      filemap[file] = 1
      print "Creating "file;
      system ("mkdir -p $(dirname "file")");
    }
    print "---" >> file;
  }
  $0!~/^# Source: / {
    if ($0!~/^---$/) {
      if (file) {
        print $0 >> file;
      }
    }
  }'

