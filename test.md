# Testing the Simulation

Goal: confirm the **sources deliver the file into every mirror** (into the hidden
folder `/var/lib/genuine/`). Each step is one copy-paste command; the explanation
is written above it. Run from the project folder:

```bash
cd "/Users/samfip/Documents/STUDY/Extra/IIT Hyderabad/NFSU"
```

---

## Step 1 — Check the sender logic locally (free, no cloud)

Runs the sender's timing/deadline logic in a sandbox. Proves it only sends when
due, reschedules randomly, and stops at the deadline.

```bash
bash scripts/test_drop.sh
```

Expect: `PASS: drop.sh honors not-due / due-reschedule / deadline-stop`.

---

## Step 2 — Bring the VMs up

Makes the login keys, loads your Linode token, and creates the machines. The
sources arm themselves at boot and start dropping.

```bash
bash scripts/make_student_keys.sh && source .env && terraform apply
```

Type `yes` when asked. Then see the addresses:

```bash
cat inventory.csv
```

Now wait ~5 minutes for boot + the first drop.

---

## Step 3 — (Optional) Check a SOURCE is armed

Confirms a source is scheduled and ready. Replace `<SOURCE_IP>` with a `source-*`
IP from `inventory.csv`.

```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@<SOURCE_IP> 'crontab -l; echo ---; ls -l /opt/sim/; echo ---; wc -l /etc/simulation/targets.txt'
```

Expect: a `* * * * * /opt/sim/drop.sh` line, the files in `/opt/sim/`, and a
targets count equal to your mirror count.

---

## Step 4 — Confirm the file reached the mirrors (the main check)

Lists the hidden drop folder on one mirror. Replace `<MIRROR_IP>` with a
`mirror-*` IP from `inventory.csv`.

```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@<MIRROR_IP> 'ls -l --time-style=full-iso /var/lib/genuine/'
```

Expect `malicious_test.txt` in the listing. If it's there, the source delivered it.
(If not yet, wait a minute and run again — drops happen every 3-4 min.)

**Check all mirrors at once** (reads the IPs from inventory.csv):

```bash
for ip in $(awk -F, '$2=="mirror"{print $4}' inventory.csv | tr -d '\r'); do echo "== $ip =="; ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$ip 'ls -l /var/lib/genuine/' 2>/dev/null; done
```

Expect `malicious_test.txt` on every mirror.

---

## Step 5 — Tear everything down

Deletes all the VMs so they stop billing.

```bash
bash destroy.sh
```

---

## Notes

- The file is dropped into `/var/lib/genuine/` (set by `dest_dir` in `config.yaml`),
  a folder students aren't told about.
- The sim auto-stops sending after 15 minutes (cron removes itself), but the VMs
  keep billing until you run `bash destroy.sh`.
- Cron runs once a minute, so the first file appears ~4-6 min after `apply`, not to
  the exact second.
- IPs change every time you re-create the VMs. Always read the current ones from
  `inventory.csv`.
