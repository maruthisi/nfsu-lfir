#!/usr/bin/env bash
# Generate one SSH login keypair per mirror, into the repo-root keys/students/.
# Count comes from mirror.yaml. Idempotent: existing keys are kept.
# Run BEFORE `terraform apply`.
set -eu
cd "$(dirname "$0")/.."                 # iac/opentofu (for mirror.yaml)
COUNT=$(grep -E '^count:' mirror.yaml | head -1 | awk '{print $2}')
KEYS="../../keys/students"              # keys live at the repo root
mkdir -p "$KEYS"
for i in $(seq 1 "$COUNT"); do
  name=$(printf "mirror-%02d" "$i")
  key="$KEYS/$name"
  if [ -f "$key" ]; then
    echo "keep   $key"
  else
    ssh-keygen -t ed25519 -f "$key" -N "" -C "student-$name" >/dev/null
    echo "create $key(.pub)"
  fi
done
echo "done: $COUNT student keys in keys/students/"
