#!/usr/bin/env bash
# Reliable teardown. `terraform destroy` needs the Events token scope and 401s
# without it; this deletes all source-*/mirror-* Linodes via the API (needs only
# Linodes = Read/Write), clears Terraform state, and empties the Ansible inventory.
set -u
cd "$(dirname "$0")"                 # iac/opentofu
source ../../.env                    # shared secrets live at the repo root
TOKEN="$TF_VAR_linode_token"

curl -s -H "Authorization: Bearer $TOKEN" \
  "https://api.linode.com/v4/linode/instances?page_size=200" \
 | python3 -c 'import sys,json,re
d=json.load(sys.stdin)
for x in d.get("data",[]):
    if re.match(r"(source|mirror)-", x["label"]):
        print(x["id"])' | while IFS= read -r id; do
  id="${id//[$'\r\n ']/}"; [ -n "$id" ] || continue
  code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
    -H "Authorization: Bearer $TOKEN" "https://api.linode.com/v4/linode/instances/$id")
  echo "deleted linode $id -> HTTP $code"
done

terraform state rm linode_instance.source linode_instance.mirror 2>/dev/null || true
rm -f inventory.csv handout.csv

# Empty the Ansible inventory so it holds no stale IPs after teardown.
cat > ../ansible/inventory/hosts.yml <<'YML'
all:
  vars:
    ansible_user: root
    ansible_ssh_private_key_file: ~/.ssh/id_ed25519
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
  children:
    sources:
      hosts: {}
    mirrors:
      hosts: {}
YML
echo "ansible inventory emptied."
echo "teardown complete."
