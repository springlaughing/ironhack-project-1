# Runbook: database failover to zone b

**Use this when zone a fails and C1, the primary database, is gone.**
At the end, C2 is the primary database, the name `db-write` points to it, and
the votes that waited during the outage are saved. The apps don't change.

**Stay calm: nothing is being lost.** While you work, new votes wait safely in
Redis b (zone b's queue, saved to disk). Only the results page stops updating.
Take the time to read each step.

**Why this is manual:** promoting a database can't be undone. A person decides.

**Tested for real on 14 Oct 2026:** zone a stopped during 10 votes per second;
8,855 votes accepted, 8,855 saved, 0 lost. The example outputs below are from
that test.

Every step has the same parts:
- **Why**: what the step is for
- **Do**: the commands, copy them as they are
- **What this does**: each command in plain words
- **Expect**: what you should see
- **If not**: what to do instead

---

## How to read the commands

Most commands run something on one server through Ansible (over Session Manager):

```bash
ansible evgenia-voting-c2 -b -m command -a "docker exec voting-db-1 psql -U postgres -tAc 'SELECT 1'"
```

| Part | Meaning |
|---|---|
| `ansible evgenia-voting-c2` | run on server C2 |
| `-b` | as root (Docker needs it) |
| `-m command -a "…"` | the command to run there |
| `docker exec voting-db-1` | inside the database container |
| `psql -U postgres` | PostgreSQL's command-line tool, as user `postgres` |
| `-tAc '…'` | print only the value (`-t` no headers, `-A` no padding) of this SQL (`-c`) |

Ansible prints the server name, `CHANGED | rc=0 >>`, and on the next line the
answer. `CHANGED` only means "a command ran", nothing was modified. A long
`aws_ssm` traceback may appear too; it is harmless.

Server IDs are never written into this runbook, because they change when a
server is rebuilt. Where AWS needs an ID, the step looks it up by the server's
name first and shows it with `echo`.

**The timeline file.** Each step ends with a line like:

```bash
echo "$(date -u +%T) C2 promoted" >> ~/failover-times.txt
```

What this does: `date -u +%T` prints the time now in UTC (e.g. `10:49:13`),
`$( … )` puts it into the text, and `>> ~/failover-times.txt` adds the line to
the end of a file in your home folder, without printing anything. Afterwards
`cat ~/failover-times.txt` shows the whole outage, minute by minute: when it
started, how long each step took. That is the record for the post-mortem.

---

## 0. Get ready

**Do:**
```bash
cd ~/ironhack/ironhack-project-1/ansible
```

**What this does:** goes into the repo's `ansible` folder. Ansible reads its
settings and its list of servers from this folder, so every `ansible` command
below must run from here.

**Use one terminal for the whole runbook.** Steps 3 and W1 keep server IDs in
variables (`C1_ID`, …); variables exist only in the terminal where they were
created.

---

## 1. Detect

**Why:** this is the trigger.

The email **"ALARM: evgenia-voting-vote-servers-down"** arrives, or votes stop
appearing on the results page.

How to read the email (example from the test):

> Threshold Crossed: 1 datapoint [1.0 (14/10/26 10:38:00)] was less than the
> threshold (2.0).

In the minute starting 10:38, there was only **1** healthy Vote server behind
the load balancer, and the rule is "fewer than 2 = alarm". So one Vote server is
gone. That alone does not mean the database is gone: step 2 checks that.

The email arrives about 3–5 minutes after the outage (CloudWatch first collects
a full minute of data, then evaluates it).

**Do:**
```bash
echo "$(date -u +%T) alarm email" >> ~/failover-times.txt
```

**What this does:** writes the time you noticed the alarm into the timeline
file (see "The timeline file" above). The gap between the email's own time and
this time is your reaction time, part of the honest recovery time.

---

## 2. Confirm: is C1 really gone?

**Why:** a failover is only for a lost **primary database**. If only a Vote
server is down and C1 is fine, a failover would cause more harm than good: it
would create a second primary.

**Do:**
```bash
aws ec2 describe-instances --filters "Name=tag:Name,Values=evgenia-voting-*" \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value,State.Name]' --output table
```

**What this does:** asks AWS for all servers whose name starts with
`evgenia-voting-` and prints a table of each name and its state (`running`,
`stopping`, `stopped`).

**Expect (failover needed):** `evgenia-voting-c1` is `stopped` or `stopping`
(in the test: a1, b1, c1 stopped; a2, b2, c2 running).

**If C1 shows `running`,** ask its database directly:

```bash
ansible evgenia-voting-c1 -b -m command -a "docker exec voting-db-1 psql -U postgres -tAc 'SELECT 1'"
```

**What this does:** runs the simplest possible SQL, `SELECT 1` ("are you
alive?"), in C1's database. A working database answers `1`.

- Answers `1`: C1 is fine. **Stop here, no failover.** Fix the broken Vote
  server instead (restart it, check its logs).
- `UNREACHABLE`, `FAILED` or no answer: C1's database is gone. Go on.

**Do:**
```bash
echo "$(date -u +%T) confirmed: C1 is gone" >> ~/failover-times.txt
```

**What this does:** notes the time of the decision in the timeline file.

---

## 3. Fence C1: make sure it can't take writes

**Why:** if C1 came back on its own, its database would still believe it is the
primary. Two primaries means two different sets of votes that can't be merged
("split brain"). Stopping C1 for good prevents that.

**Do:**
```bash
C1_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=evgenia-voting-c1" \
  --query 'Reservations[].Instances[].InstanceId' --output text)
echo "$C1_ID"
```

**What this does:** asks AWS for the ID of the server named
`evgenia-voting-c1`, keeps it in a variable called `C1_ID` (`C1_ID=$( … )`),
and shows it, so you can check it before anything uses it.

**Expect:** one ID, like `i-0c8aa876f3506e5e1`.
**If nothing or two IDs:** stop and look at the table from step 2.

```bash
aws ec2 stop-instances --instance-ids "$C1_ID"
aws ec2 wait instance-stopped --instance-ids "$C1_ID"
echo "$(date -u +%T) C1 fenced (stopped)" >> ~/failover-times.txt
```

**What this does:** `stop-instances` asks AWS to stop C1 (if it is already
stopped, AWS just answers `stopped`). `wait instance-stopped` waits until AWS
reports it stopped; it returns without output. The last line notes the time.

**If AWS can't stop it** (zone a unreachable, the command hangs or fails): go on
anyway. Step 5 moves every app away from C1. Write down that C1 was **not**
stopped, and never start C1 without following "Way back" below.

---

## 4. Promote C2

**Why:** C2 is a read-only copy of C1. Promoting makes it a normal, writable
primary database.

**Do, first the check:**
```bash
ansible evgenia-voting-c2 -b -m command -a "docker exec voting-db-1 psql -U postgres -tAc 'SELECT pg_is_in_recovery(), pg_last_xact_replay_timestamp()'"
```

**What this does:** asks C2 two questions. `pg_is_in_recovery()`: "are you
still a copy?" (PostgreSQL calls a copy that keeps replaying the primary's
changes "in recovery"). `pg_last_xact_replay_timestamp()`: "when did the last
change from C1 arrive?"

**Expect:** `t|2026-…` (test: `t|2026-10-14 10:37:55.25+00`). `t` = C2 is still
a copy, safe to promote. The time is the last change C2 received from C1;
anything C1 saved after that moment is not on C2. Write it down.

**If `f`:** C2 is already a primary; someone promoted it. Skip to step 5.
**If UNREACHABLE:** C2 is not reachable either. Stop and investigate: there is
no copy to fail over to.

**Do, the promotion (cannot be undone):**
```bash
ansible evgenia-voting-c2 -b -m command -a "docker exec voting-db-1 psql -U postgres -tAc 'SELECT pg_promote()'"
```

**What this does:** tells PostgreSQL on C2 to stop being a copy: it stops
waiting for C1, deletes its `standby.signal` file (the marker "I am a copy")
and starts accepting writes. It answers `t` when the promotion has finished.

```bash
ansible evgenia-voting-c2 -b -m command -a "docker exec voting-db-1 psql -U postgres -tAc 'SELECT pg_is_in_recovery()'"
echo "$(date -u +%T) C2 promoted" >> ~/failover-times.txt
```

**What this does:** asks C2 again "are you still a copy?", then notes the time.

**Expect:** `f`: C2 is no longer a copy, it is the primary.
**If still `t`:** wait 10 seconds and ask again; promotion takes a few seconds.

**Votes still wait after this step.** The Worker looks for the database under
the name `db-write`, which still points to C1. That is step 5.

---

## 5. Move the names to C2

**Why:** the apps find the database by name (`db-write`, `db-read-a`). Pointing
the names at C2 is what sends the Worker and the results page there. No app
changes, no restarts.

**Do:** open `terraform/infra/variables.tf`, find `variable "db_primary"`, and
change its default:

```hcl
  default     = "c2"
```

**What this does:** tells Terraform that C2 is now the primary; `dns.tf` then
points `db-write` and `db-read-a` at C2's address. Change the file, don't use
`-var`: then a later `terraform apply` can't quietly move the names back to C1.

```bash
cd ../terraform/infra
terraform plan
```

**What this does:** `cd` goes from the `ansible` folder up one level and into
the Terraform folder. `terraform plan` compares the files with what exists in
AWS and lists what it would change. It changes nothing itself.

**Expect:** `Plan: 0 to add, 2 to change, 0 to destroy`: `db-read-a` and
`db-write`, each `~ update in-place`, records `- "10.0.20.68"` (C1)
`+ "10.0.21.196"` (C2).

**If the plan shows anything else:** stop and read it. Do not apply a plan you
don't understand.

```bash
terraform apply      # type yes
```

**What this does:** makes the plan real: updates the two address records in
the private zone `voting.internal`. Takes 30–60 seconds.

**Expect:** `Apply complete! Resources: 0 added, 2 changed, 0 destroyed.`

```bash
cd ../../ansible
echo "$(date -u +%T) db-write moved to C2" >> ~/failover-times.txt
```

**What this does:** goes back up two levels and into the `ansible` folder for
the next step, and notes the time.

Servers may remember the old address for up to 60 seconds (the records'
time-to-live). In the test, votes were saved again 30 seconds after the apply.

---

## 6. Check that votes are saved again

**Why:** proof that the failover worked, end to end.

**Do:**
```bash
ansible evgenia-voting-b2 -m command -a "getent hosts db-write.voting.internal"
```

**What this does:** asks B2's operating system which address the name
`db-write.voting.internal` has right now: the same lookup the Worker uses.

**Expect:** `10.0.21.196     db-write.voting.internal` (C2).
**If `10.0.20.68`:** B2 still remembers the old answer. Wait a minute, repeat.

```bash
ansible evgenia-voting-c2 -b -m command -a "docker exec voting-redis-1 redis-cli LLEN votes"
```

**What this does:** asks Redis on C2 how many votes are waiting in the list
`votes` (`LLEN` = list length).

**Expect:** a number going down to `0` when you repeat it. In the test, 7,468
waiting votes were saved in 10 seconds.

**If it doesn't go down after 2 minutes:** look at the Worker on B2:

```bash
ansible evgenia-voting-b2 -b -m shell -a "docker logs --tail 20 \$(docker ps --filter name=worker -q | head -1)"
```

**What this does:** finds the first Worker container on B2
(`docker ps --filter name=worker -q`) and shows its last 20 log lines.
(`-m shell` because of the `$( … )`; the `\` keeps your own terminal from
running that part, so it runs on B2.)

```bash
echo "$(date -u +%T) queue empty: votes are saved again" >> ~/failover-times.txt
```

**What this does:** notes the moment saving works again: the end of the outage
for the results page.

Then open the results page: new votes appear again.

---

## 7. Record the new roles

**Why:** Ansible decides by `db_role` which server is the primary. It must
match reality before any playbook runs again. With the old roles,
`replica-init.yml` (Way back, W3) would refuse to rebuild C1, and would be
allowed to rebuild **C2**, deleting the database that now holds all votes.

**Do:** change one line in each file:

- `ansible/inventory/host_vars/evgenia-voting-c1.yml`: `db_role: replica`
- `ansible/inventory/host_vars/evgenia-voting-c2.yml`: `db_role: primary`

**What this does:** updates Ansible's notes about which server is which. No
playbook runs now; the notes take effect at the next run.

Commit this together with the `variables.tf` change:

```bash
cd ..
git add terraform/infra/variables.tf ansible/inventory/host_vars/
git status
git commit -m "fix: fail over the database to C2"
cd ansible
echo "$(date -u +%T) roles recorded, failover committed" >> ~/failover-times.txt
```

**What this does:** `cd ..` goes to the repo root. `git add` marks the changed
files for the commit; `git status` shows what will be committed (expect exactly
3 files: `variables.tf` and the two host_vars files); `git commit` saves them
as one step in the history, the record of the failover. Then back into
`ansible`, and the time is noted.

**The outage is handled.** The rest can wait until zone a is back.

---

## Way back: when zone a returns

C2 stays the primary. C1 comes back as its copy, so there is no second switch
and no second interruption.

### W1. Start zone a

```bash
A1_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=evgenia-voting-a1" --query 'Reservations[].Instances[].InstanceId' --output text)
B1_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=evgenia-voting-b1" --query 'Reservations[].Instances[].InstanceId' --output text)
C1_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=evgenia-voting-c1" --query 'Reservations[].Instances[].InstanceId' --output text)
echo "A1 $A1_ID  B1 $B1_ID  C1 $C1_ID"
```

**What this does:** looks up the three zone a servers' IDs by name, keeps each
in a variable, and shows them. **Expect:** three IDs.

```bash
aws ec2 start-instances --instance-ids "$A1_ID" "$B1_ID" "$C1_ID"
aws ec2 wait instance-running --instance-ids "$A1_ID" "$B1_ID" "$C1_ID"
echo "$(date -u +%T) zone a started" >> ~/failover-times.txt
```

**What this does:** switches the three servers on, waits until AWS reports them
running (about a minute), and notes the time. Their disks still hold everything:
C1's old database and Redis a with any votes that were waiting. Docker starts
the containers by itself (`restart: unless-stopped`).

C1's old database starts too and still believes it is the primary. That is safe
for now: nothing uses it, because all names point to C2. **Don't point anything
at C1.**

### W2. Check before rebuilding C1

**Why:** votes that were waiting in Redis a when zone a went down are still on
C1's disk. B1's Worker saves them to `db-write`, which is now C2. And C1's old
database still shows what C1 had saved, so this is the moment to check nothing
was lost. Do this **before** W3, which deletes C1's old database.

```bash
ansible evgenia-voting-c1 -b -m command -a "docker exec voting-redis-1 redis-cli LLEN votes"
```

**What this does:** how many votes still wait in Redis a. **Expect:** `0`
(B1's Worker takes them out within seconds of starting).

```bash
ansible evgenia-voting-c1 -b -m command -a "docker exec voting-db-1 psql -U postgres -tAc 'SELECT COUNT(*) FROM votes'"
ansible evgenia-voting-c2 -b -m command -a "docker exec voting-db-1 psql -U postgres -tAc 'SELECT COUNT(*) FROM votes'"
```

**What this does:** counts all votes in C1's old database and in C2.
**Expect:** C2's number is larger (it has everything since the outage). If you
noted C2's count before the promotion (step 4), it should equal C1's number:
then C2 had received everything C1 ever saved.

### W3. Turn C1 into the copy of C2

**Why:** C1's old database must not come back as a primary. This deletes it and
copies C2's database instead.

```bash
ansible-playbook replica-init.yml -e confirm=yes
echo "$(date -u +%T) C1 is now the copy of C2" >> ~/failover-times.txt
```

**What this does:** runs the one-off playbook `replica-init.yml`. On the server
with `db_role: replica` (C1, after step 7) it stops the database, deletes the
old data folder, copies C2's whole database with `pg_basebackup` from
`db-write` (now C2), and starts it as a read-only copy that follows C2. On C2
(`db_role: primary`) it only checks the role and stops. `-e confirm=yes` is the
safety catch: without it the playbook does nothing at all, because deleting a
database should never happen by accident.

**Expect:** in the recap, C1 has several `changed`, C2 has `changed=0`, both
`failed=0`.
**If it fails:** C2 keeps working the whole time; only the copy is missing.
Read the error before trying again.

### W4. Check

```bash
ansible evgenia-voting-c2 -b -m command -a "docker exec voting-db-1 psql -U postgres -tAc 'SELECT client_addr, state FROM pg_stat_replication'"
```

**What this does:** asks C2 which copies are connected and receiving its
changes. **Expect:** `10.0.20.68|streaming` (C1, receiving live).

```bash
ansible evgenia-voting-c1 -b -m command -a "docker exec voting-db-1 psql -U postgres -tAc 'SELECT pg_is_in_recovery()'"
```

**What this does:** asks C1 "are you a copy?". **Expect:** `t`.

```bash
ansible 'evgenia-voting-c*' -b -m command -a "docker exec voting-db-1 psql -U postgres -tAc 'SELECT COUNT(*) FROM votes'"
```

**What this does:** counts all votes on both data servers (the pattern
`evgenia-voting-c*` matches C1 and C2). **Expect:** the same number twice.

```bash
echo "$(date -u +%T) way back done: C2 primary, C1 streaming copy" >> ~/failover-times.txt
cat ~/failover-times.txt
```

**What this does:** notes the end, then prints the whole timeline of the outage.

**The roles have swapped:** C2 is the primary, C1 its copy. If zone b fails
next, follow this runbook with C1 and C2 (and zone a and b) the other way round.

Known limit: zone a now reads from C2 across zones (`db-read-a` follows the
primary). That works; pointing it back at C1 is an outlook item.