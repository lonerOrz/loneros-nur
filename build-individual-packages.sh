#!/usr/bin/env bash

# Script to build each package individually and run garbage collection after each build
# This helps to save disk space in CI environments

set -e

echo "Fetching all cacheable outputs from ci.nix..."

# Get the list of all cacheable outputs
output_paths=$(nix eval --impure --expr "
  let
    ci = import ./ci.nix {};
  in
    builtins.map (x: x.outPath) ci.cacheOutputs
" --json)

# Parse the JSON output to get an array of paths
mapfile -t output_paths_array < <(echo "$output_paths" | jq -r '.[]')

echo "List of outputs to build:"
printf '%s\n' "${output_paths_array[@]}"

# Change to the project directory
cd "$(dirname "$0")"

total=${#output_paths_array[@]}
count=0

for output_path in "${output_paths_array[@]}"; do
  count=$((count+1))
  echo "[$count/$total] Building output: $output_path"

  # Build the specific output path
  nix build --no-link --print-out-paths "$output_path" -L

  # Run garbage collection to clean up intermediate build artifacts
  echo "Running garbage collection..."
  nix-collect-garbage -d

  echo "Successfully built: $output_path"
done

echo "All packages built successfully with individual garbage collection."