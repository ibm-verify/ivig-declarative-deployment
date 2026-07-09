#!/bin/bash

[ ! -f "$1" ] || { sed -n 's/^e \([^[:space:]]*\) "\([[:alnum:]]*\)/\2  \1/p' < "$1" | sha1sum -c && ex < "$1"; }
