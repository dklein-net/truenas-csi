#!/usr/bin/env bash
# resolve-image-digests.sh
#
# Post-processes a ClusterServiceVersion YAML to:
#   1. Replace image tags in env var values with @sha256: digests
#   2. Rebuild the relatedImages section from all digest-pinned images
#
# Usage: ./hack/resolve-image-digests.sh <csv-file>

set -euo pipefail

CSV="${1:?Usage: $0 <csv-file>}"

if [[ ! -f "$CSV" ]]; then
  echo "Error: CSV file not found: $CSV" >&2
  exit 1
fi

# resolve_digest takes an image:tag and returns image@sha256:...
resolve_digest() {
  local image="$1"
  local digest

  # Skip if already pinned to a digest
  if [[ "$image" == *"@sha256:"* ]]; then
    echo "$image"
    return
  fi

  echo "  Resolving: $image" >&2
  digest=$(docker manifest inspect "$image" -v 2>/dev/null | \
    grep -m1 '"digest"' | sed 's/.*"digest": *"//;s/".*//')

  if [[ -z "$digest" ]]; then
    echo "  Warning: Could not resolve digest for $image, keeping tag" >&2
    echo "$image"
    return
  fi

  # Strip tag and append digest
  local repo="${image%%:*}"
  echo "${repo}@${digest}"
}

echo "Resolving image digests in $CSV..."

# Collect all image references from env var value fields (lines matching "value: <registry>/")
# and from the container image field
mapfile -t IMAGE_LINES < <(grep -n 'value: .*\(registry\|quay\.io\)' "$CSV")

declare -A REPLACEMENTS

for line in "${IMAGE_LINES[@]}"; do
  # Extract the image reference (everything after "value: ")
  image=$(echo "$line" | sed 's/.*value: *//')
  # Skip if already a digest
  if [[ "$image" == *"@sha256:"* ]]; then
    continue
  fi
  resolved=$(resolve_digest "$image")
  if [[ "$image" != "$resolved" ]]; then
    REPLACEMENTS["$image"]="$resolved"
  fi
done

# Apply replacements to the CSV
for original in "${!REPLACEMENTS[@]}"; do
  resolved="${REPLACEMENTS[$original]}"
  echo "  $original -> $resolved" >&2
  sed -i "s|${original}|${resolved}|g" "$CSV"
done

# Now rebuild relatedImages from all image@sha256: references in the file
echo "Rebuilding relatedImages section..."

# Collect all unique digest-pinned images from the CSV (excluding the relatedImages section itself)
# We look for image references in both `image:` and `value:` fields
mapfile -t ALL_IMAGES < <(
  sed '/^  relatedImages:/,/^  [a-z]/d' "$CSV" | \
  grep -oE '(registry\.[a-z0-9.]+|quay\.io)/[a-zA-Z0-9_./-]+@sha256:[a-f0-9]+' | \
  sort -u
)

# Build the new relatedImages block
RELATED="  relatedImages:"
for img in "${ALL_IMAGES[@]}"; do
  # Generate a name from the image path
  # e.g., registry.k8s.io/sig-storage/csi-provisioner@sha256:abc -> csi-provisioner
  name=$(echo "$img" | sed 's|.*/||; s|@.*||')
  RELATED="${RELATED}
    - image: ${img}
      name: ${name}"
done

# Replace the existing relatedImages section
# Delete from "  relatedImages:" to the next top-level field (or end of spec)
# Then insert the new block
python3 -c "
import re, sys

csv = open('$CSV').read()

# Match relatedImages section: from '  relatedImages:' to next '  <field>:' at same indent or end of file
pattern = r'  relatedImages:.*?(?=\n  [a-z]|\Z)'
replacement = '''$RELATED'''

csv = re.sub(pattern, replacement, csv, flags=re.DOTALL)
open('$CSV', 'w').write(csv)
"

echo "Done. Related images:"
grep -A1 'name:' "$CSV" | grep 'image:' | sed 's/.*image: /  /'
