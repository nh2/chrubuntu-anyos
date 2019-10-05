#!/usr/bin/env bash

set -euo pipefail

mkdir -p download/files
mkdir -p download/shas

# Download files (~1GB) with the `aria2c` downloader
(cd download/files && bash ../../echo-download-files.sh | aria2c -i -)

# Download checksums
(cd download/shas && bash ../../download-shas.sh)

# Check checksums and combine file parts into final file
(cd download/files && bash ../../check-shas.sh)
