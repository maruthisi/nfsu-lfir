#!/usr/bin/env bash
# Generate one SSH login keypair per mirror, into keys/students/mirror-NN[.pub].
# Count comes from mirror.yaml. Idempotent: existing keys are kept, so a student's
# key stays the same across re-applies. Run this BEFORE `terraform apply`.
set -eu
cd "$(dirname "$0")/.."
COUNT=$(grep -E '^count:' mirror.yaml | head -1 | awk '{print $2}')
mkdir -p keys/students
for i in $(seq 1 "$COUNT"); do
  name=$(printf "mirror-%02d" "$i")
  key="keys/students/$name"
  if [ -f "$key" ]; then
    echo "keep   $key"
  else
    ssh-keygen -t ed25519 -f "$key" -N "" -C "student-$name" >/dev/null
    echo "create $key(.pub)"
  fi
done
echo "done: $COUNT student keys in keys/students/"
