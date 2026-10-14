#!/bin/bash
# Copyright IBM Corp. 2026
# SPDX-License-Identifier: MIT

[[ -x $1 ]] && "$1" || echo "HOT PATCHING: skipped, no patch for this version"
