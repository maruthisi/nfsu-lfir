# Controlled File-Drop Security Simulation (Linode, 28 VMs)

3 source VMs (spread across non-India regions) periodically `scp` a **harmless**
`.txt` file to 25 user VMs (Mumbai) at randomized 3–4 min intervals for a hard
15-minute window, then stop. Students log into their own user VM and work out
**which machine sent the file and its IP** from the *natural* trail only —
sshd's login records in the systemd journal (`journalctl`) plus the dropped file's mtime. No custom logging is
created anywhere.

Config is split across three files: **`config.yaml`** (shared: duration, image,
filename, intervals), **`mirror.yaml`** (the machines under attack), and
**`source.yaml`** (the malicious senders). Terraform reads all three with
`yamldecode()`; the source scripts read the values baked in from them.

## Layout

```
config.yaml          # shared: duration, instance type, image, filename, intervals
mirror.yaml          # MIRROR machines under attack: count + region
source.yaml          # SOURCE senders: count + regions
providers.tf         # linode + random + local providers (event polling skipped)
variables.tf         # linode_token (sensitive), mgmt_ssh_pubkey
main.tf              # mirror + source instances, inventory.csv
outputs.tf           # source/mirror tables (the answer key + hand-out list)
templates/           # cloud-init for mirrors and sources
scripts/drop.sh      # cron wrapper: due-check + scp + hard-deadline stop
scripts/setup_once.sh# first-boot: fixes the window + writes the harmless file
scripts/test_drop.sh # local self-check for the timing/deadline logic (no cloud)
keys/                # your hand-made shared key (gitignored)
```

## Run

```bash
# 1. Make the shared source->mirror attack key BY HAND (once). Already done if keys/ exists.
ssh-keygen -t ed25519 -f keys/sim_key -N ""

# 2. Make one login key per mirror (reads count from mirror.yaml).
bash scripts/make_student_keys.sh

# 3. Credentials: paste your token into .env (mgmt key is prefilled), then load it.
source .env            # see "Getting a Linode API token" below

# 4. Sanity-check the sender logic locally (optional, no cloud needed).
bash scripts/test_drop.sh

# 5. Provision. VMs boot, the sim auto-starts, runs 15 min, self-stops.
terraform init
terraform apply

# 6. Hand-out / answer key.
cat inventory.csv         # label,role,region,public_ip for every VM
cat handout.csv           # mirror -> IP -> student key file -> login command

# 7. Tear everything down when the exercise is over.
bash destroy.sh          # API-based teardown (terraform destroy needs Events scope)
```

## Where the keys live

All under `keys/` (gitignored — never commit):

| Key | File(s) | Who uses it |
|-----|---------|-------------|
| Shared **attack** key (sources -> mirrors) | `keys/sim_key`, `keys/sim_key.pub` | the simulation — **never hand out** |
| **Student** login keys (one per mirror) | `keys/students/mirror-01`, `.../mirror-01.pub`, ... | each student, into their own mirror |
| Your **management** key | your `~/.ssh/id_ed25519.pub` (set in `.env`) | you, as `root` on every VM |

`handout.csv` (written by `apply`) maps each mirror to its IP, its private key
file, and the exact login command — that's what you email to each student.

## How to test by logging into a VM (step by step)

You (instructor) log in as `root` on any VM using your own key. A student logs in
as `analyst` on their own mirror using the student key you emailed them.

**A. As the instructor (root) — verify a source is sending:**
```bash
ssh -o StrictHostKeyChecking=accept-new root@<SOURCE_IP> 'crontab -l; ls -l /opt/sim/'
```
`<SOURCE_IP>` = a `source-*` IP from `inventory.csv`. You should see the cron line
and the files in `/opt/sim/`.

**B. As the instructor (root) — verify a file landed and read the trail:**
```bash
ssh root@<MIRROR_IP> 'ls -l --time-style=full-iso /home/analyst/; cat /home/analyst/malicious_test.txt; journalctl _COMM=sshd | grep -i accepted'
```
`<MIRROR_IP>` = a `mirror-*` IP. You should see `malicious_test.txt` and an
`Accepted publickey ... from <SOURCE_IP>` line.

**C. As a student (analyst) — exactly what a candidate does:**
```bash
# The student receives their key file (e.g. mirror-07) + their IP by email.
chmod 600 mirror-07                               # email attachments lose permissions
ssh -i mirror-07 analyst@<THEIR_MIRROR_IP>        # log into their own machine

# Once logged in, they investigate:
ls -l --time-style=full-iso ~/                    # find malicious_test.txt + its time
cat ~/malicious_test.txt                          # confirm it's the dropped file
sudo journalctl _COMM=sshd | grep -i accepted     # -> "from <SOURCE_IP>" = the sender
```
The IP in the `Accepted ... from` line, at the same time as the file's timestamp,
is the machine that sent the file — the answer the student reports.

## Getting a Linode API token

1. Log in at <https://cloud.linode.com>.
2. Top-right avatar -> **API Tokens** (direct link: <https://cloud.linode.com/profile/tokens>).
3. **Create a Personal Access Token** -> label it, set an expiry (a few hours is plenty).
4. Scopes: set **Linodes = Read/Write**. (That's all that's needed — the provider is
   configured to skip Event polling, so no Events scope is required.)
5. Click **Create**, then **copy the token immediately** — Linode shows it only once.
6. Paste it into `export TF_VAR_linode_token="..."`.

No Linode account yet? Sign up at <https://cloud.linode.com/signup>, add a payment
method (28 nanodes cost ~$0.19/hr while running), then follow the steps above.

## How the timing works (spec §4–§6)

- At first boot each source fixes `end_epoch = now + duration_seconds` and a
  random `next_epoch`.
- `cron` runs `drop.sh` every minute. It: (a) if `now >= end_epoch`, deletes its
  own cron line and exits — **clean stop, no drop at or after the deadline**;
  (b) if not yet `next_epoch`, does nothing; (c) otherwise scp's the file to all
  users and re-rolls `next_epoch` 180–240 s ahead.
- Randomization is per-host, so the three sources are never synchronized.
- Known limit: cron granularity is 1 minute, so a drop lands on the next minute
  tick after its randomized due time (not to-the-second).

## Scaling (no code changes)

- Add/remove MIRROR machines: edit `mirror.yaml` -> `count`.
- Add/remove SOURCE machines: edit `source.yaml` -> `count` (add a matching `regions:` entry).
- Duration / intervals / filename: edit `config.yaml`.
- `duration_seconds: 1800` -> 30-minute run.
- `simulation.duration_seconds: 1800` → 30-minute run.
- `file_transfer.filename` / interval bounds → changeable without touching scripts.

## The investigation (instructor answer key — NOT on the VMs)

On a user VM, correlate the file's mtime with the sshd login at that instant:

```bash
ls -l --time-style=full-iso ~/malicious_test.txt   # -> mtime, e.g. 15:03:xx
journalctl _COMM=sshd | grep -i accepted           # this image has no /var/log/auth.log
#  ... Accepted publickey for analyst from <SOURCE_PUBLIC_IP> port ... ssh2
```

The sender = the public IP in the journal's Accepted line whose timestamp matches the file
mtime. A `whois` / geolocation lookup on that IP even reveals the source's
region (US / UK / Singapore — clearly foreign to a Mumbai lab).

## Notes

- Uses public IPs (no VLAN): sources are in different regions, so no shared
  private LAN can span them.
- `~28 x g6-nanode-1` bills by the hour (~$0.19/hr total). Run `terraform destroy`
  promptly.
