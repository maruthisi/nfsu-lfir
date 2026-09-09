# Testing the Simulation

Two-stage pipeline:

1. **OpenTofu/Terraform** (`iac/opentofu/`) provisions the VMs. They boot with
   **nginx already running** (serving `/var/data`) and OpenTofu writes the Ansible
   inventory (`iac/ansible/inventory/hosts.yml`).
2. **Ansible** (`iac/ansible/`) deploys the file-drop sender onto the sources.

> **Run each numbered step from the repo root.** Each block `cd`s where it needs to
> go, so start every block from the repo root (`cd` back there if unsure). Shared
> secrets (`keys/`, `.env`) live at the repo root.

## Prerequisites (once)

- `terraform` and `ansible` installed.
- `.env` at the repo root has your token + key:
  ```
  export TF_VAR_linode_token="<linode token, Linodes=Read/Write>"
  export TF_VAR_mgmt_ssh_pubkey="$(cat ~/.ssh/id_ed25519.pub)"
  ```
- Ansible logs in as root with `~/.ssh/id_ed25519` (your management key). If your key
  is elsewhere, change `ansible_ssh_private_key_file` in the `local_file "ansible_hosts"`
  block of `iac/opentofu/main.tf` (the inventory is regenerated each apply).

---

## Step 1 — Provision (from repo root)

```bash
cd iac/opentofu
bash scripts/make_student_keys.sh
source ../../.env
terraform init
terraform apply
cat ../ansible/inventory/hosts.yml     # confirm the inventory was generated
```

Type `yes` at the prompt. Give the VMs ~2-3 min to finish booting (cloud-init + nginx).

---

## Step 2 — Run the drops (from repo root)

```bash
cd iac/ansible
ansible -i inventory/hosts.yml all -m ping
ansible-playbook -i inventory/hosts.yml playbooks/drop_files.yml
```

`ping` should return `SUCCESS`/`pong` from every host. The playbook deploys a cron'd
sender onto each source that scp's `malicious_test.txt` to every mirror's `/var/data`
at random 3-4 min intervals for a 15-min window, then self-stops.

---

## Step 3 — Verify (from repo root)

Wait ~4-5 min for the first drop, then:

**In a browser** — open any mirror IP (see `iac/opentofu/inventory.csv`):
```
http://<MIRROR_IP>/
```
Expect `malicious_test.txt` listed by nginx.

**Over SSH — check every mirror at once:**
```bash
for ip in $(awk -F, '$2=="mirror"{print $4}' iac/opentofu/inventory.csv | tr -d '\r'); do
  echo "== $ip =="
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$ip 'ls -l /var/data/' 2>/dev/null
done
```
Expect `malicious_test.txt` on every mirror.

**Check a source is armed (optional):**
```bash
SRC=$(awk -F, '$2=="source"{print $4}' iac/opentofu/inventory.csv | tr -d '\r' | head -1)
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$SRC" 'crontab -l; ls -l /opt/sim/ /var/data/'
```
Expect the `* * * * * /opt/sim/drop.sh` cron line and the files.

---

## Step 4 — Tear everything down (from repo root)

```bash
bash iac/opentofu/destroy.sh
cat iac/ansible/inventory/hosts.yml     # now empty: sources/mirrors present, hosts: {}
```

Deletes all VMs and empties the Ansible inventory.

---

## Notes

- OpenTofu only **provisions** (+ nginx at boot). The copy + randomized timing live in
  Ansible (`playbooks/drop_files.yml`); its `vars:` are the knobs.
- `hosts.yml` is regenerated on every `apply`, emptied by `destroy.sh`.
- IPs change on each re-create — always read them from `hosts.yml` or `inventory.csv`.
- Admin access: your key comes from `.env`; extra admins go one-per-line in
  `keys/admins.txt` and land on every VM created after the next `apply`.
- Student hand-out (mirror -> IP -> key -> login command): `iac/opentofu/handout.csv`.
- `setup_nginx_mirror.yml` is optional (nginx is already at boot); use only to reconfigure.
