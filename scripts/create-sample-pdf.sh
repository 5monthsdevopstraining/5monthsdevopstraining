#!/usr/bin/env bash
# Creates a tiny file (sample.pdf) you can upload to POST /api/files/upload.
# The .NET 10 API accepts any non-empty file up to 10 MB. Needs only bash.
set -euo pipefail
OUT="${1:-sample.pdf}"
printf '%%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 100]>>endobj\ntrailer<</Root 1 0 R>>\n%%%%EOF\n' > "$OUT"
echo "Created $OUT ($(wc -c < "$OUT") bytes)"
