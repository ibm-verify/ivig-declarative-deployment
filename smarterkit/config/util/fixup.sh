#!/bin/bash
# Copyright IBM Corp. 2026
# SPDX-License-Identifier: MIT

[ ! -f "$1" ] || { sed -n 's/^e \([^[:space:]]*\) "\([[:alnum:]]*\)/\2  \1/p' < "$1" | sha1sum -c && ex < "$1"; }
