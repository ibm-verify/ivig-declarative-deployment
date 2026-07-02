#!/usr/bin/env python3

# This script expects a flat JSON dictionary to be passed via STDIN.
# For each entry, a file with the name of key and content of value
# will be created in the current directory.
# example use: cat vault-export.json | python vault-json-to-files.py

import json
import sys

try:
    input_data = sys.stdin.read()
    if not input_data.strip():
        print("Error: Standard input is empty. JSON expected.", file=sys.stderr)
        sys.exit(1)
    data = json.loads(input_data)
except json.JSONDecodeError:
    print("Error: Input is not valid JSON.", file=sys.stderr)
    sys.exit(1)

if not isinstance(data, dict):
    print("Error: Input JSON must be a flat dictionary object.", file=sys.stderr)
    sys.exit(1)

# save a file for each entry to the current directory
for key, value in data.items():
    with open(key, "w", encoding="utf-8") as output:
        output.write(value)

print(f"Success! Processed {len(data)} entries.", file=sys.stderr)
