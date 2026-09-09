# Testing the Simulation

Two-stage pipeline:

1. **OpenTofu/Terraform** (`iac/opentofu/`) provisions the VMs. They boot with
   **nginx already running** (serving `/var/data`) and OpenTofu writes the Ansible
   inventory (`iac/ansible/inventory/hosts.yml`).
2. **Ansible** (`iac/ansible/`) deploys the file-drop sender onto the sources.

Shared secrets (`keys/`, `.env`) live at the **repo root**.

## Prerequisites (once)

- `terraform` and `ansible` installed.
- `.env` at the repo root has your token + key:
  ```
  export TF_VAR_linode_token="<linode token, Linodes=Read/Write>"
  export TF_VAR_mgmt_ssh_pubkey="$(cat ~/.ssh/id_ed25519.pub)"
  ```
- The Ansible inventory uses `~/.ssh/id_ed25519` to log in as root (that's your
  management key). If your key is elsewhere, edit `ansible_ssh_private_key_file`
  in `iac/ansible/inventory/hosts.yml` (or it's regenerated each apply — change it
  in the `local_file "ansible_hosts"` block in `iac/opentofu/main.tf`).

---

## Step 1 — Provision (OpenTofu)

```bash
cd iac/opentofu
bash scripts/make_student_keys.sh
source ../../.env
terraform init
terraform apply
```

Type `yes`. Creates the `source-*` and `mirror-*` VMs and writes the inventory.
Give them ~2-3 min to finish booting (nginx + cloud-init).

---

## Step 2 — Confirm the inventory was generated

```bash
cat ../ansible/inventory/hosts.yml
```

Expect current source and mirror IPs under `sources:` / `mirrors:`. (You can also
see them in `inventory.csv` in this folder.)

---

## Step 3 — Run the drop playbook (Ansible)

```bash
cd ../ansible
ansible -i inventory/hosts.yml all -m ping
```

Expect `SUCCESS` / `pong` from every host (proves SSH + keys work). Then start the
drops (nginx is already up from boot):

```bash
ansible-playbook -i inventory/hosts.yml playbooks/drop_files.yml
```

This deploys a cron'd sender onto each source that scp's `malicious_test.txt` to
every mirror's `/var/data` at random 3-4 min intervals for a 15-min window, then
self-stops.

---

## Step 4 — Verify the drops

Wait ~4-5 min for the first drop, then either:

**In a browser** — open a mirror IP (from `inventory.csv`):
```
http://<MIRROR_IP>/
```
Expect `malicious_test.txt` listed by nginx.

**Over SSH** — check every mirror at once:
```bash
for ip in $(awk -F, '$2=="mirror"{print $4}' ../opentofu/inventory.csv | tr -d '\r'); do
  echo "== $ip =="
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$ip 'ls -l /var/data/' 2>/dev/null
done
```
Expect `malicious_test.txt` on every mirror.

**Check a source is armed** (optional):
```bash
SRC=$(awk -F, '$2=="source"{print $4}' ../opentofu/inventory.csv | tr -d '\r' | head -1)
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$SRC 'crontab -l; ls -l /opt/sim/ /var/data/'
```
Expect the `* * * * * /opt/sim/drop.sh` cron line and the files.

---

## Step 5 — Tear everything down

```bash
cd ../opentofu
bash destroy.sh
```

Deletes all VMs and **empties** `iac/ansible/inventory/hosts.yml`. Confirm:

```bash
cat ../ansible/inventory/hosts.yml     # sources/mirrors present but hosts: {}
```

---

## Notes

- OpenTofu only **provisions** (+ installs nginx at boot). The copy + randomized
  timing live in Ansible (`playbooks/drop_files.yml`); knobs are its `vars:`.
- `hosts.yml` is regenerated on every `apply`, emptied by `destroy.sh`.
- IPs change on each re-create — always read them from `hosts.yml` or `inventory.csv`.
- Admin access: your key comes from `.env`; extra admins go one-per-line in
  `keys/admins.txt` and land on every VM created after the next `apply`.
- Student hand-out (mirror -> IP -> key -> login command): `iac/opentofu/handout.csv`.
- `setup_nginx_mirror.yml` is optional (nginx is already at boot); use only to reconfigure.
