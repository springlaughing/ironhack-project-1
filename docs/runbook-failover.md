# Runbook: database failover to zone b

**Use this when zone A fails and C1, the primary database, is gone.**
At the end, C2 is the primary database, the name `db-write` points to it, and
the votes that waited during the outage are saved. The apps don't change.

**Stay calm: nothing is being lost.** While you work, new votes wait safely in
Redis b (zone b's queue, saved to disk). Only the results page stops updating.
Take the time to read each step.

**Why this is manual:** promoting a database can't be undone. A person decides.

Every step has the same parts:
- **Why**: what the step is for
- **Do**: the commands, copy them as they are
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
answer. `CHANGED` only means "a command ran". A long `aws_ssm` traceback may
appear too; it is harmless.

Server IDs are never written into this runbook, because they change when a
server is rebuilt. Where AWS needs an ID, the step looks it up by the server's
name first and shows it with `echo`.

To keep a timeline, each step ends with a line like
`echo "$(date -u +%T) C2 promoted" >> ~/failover-times.txt`: it adds the
current time (UTC) and a note to a file in your home folder.

---

## 0. Get ready

```bash
cd ~/ironhack/ironhack-project-1/ansible
```

All commands below run from this folder, unless a step says otherwise.

---

## 1. Detect

**Why:** this is the trigger.

The email **"ALARM: evgenia-voting-vote-servers-down"** arrives (fewer than 2
healthy Vote servers), or votes stop appearing on the results page.

```bash
echo "$(date -u +%T) alarm email" >> ~/failover-times.txt
```

---

## 2. Confirm: is C1 really gone?

**Why:** a failover is only for a lost **primary database**. If only a Vote
server is down and C1 is fine, a failover would cause more harm than good.

**Do:**
```bash
# which servers are running?
aws ec2 describe-instances --filters "Name=tag:Name,Values=evgenia-voting-*" \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value,State.Name]' --output table

# does the database on C1 answer?
ansible evgenia-voting-c1 -b -m command -a "docker exec voting-db-1 psql -U postgres -tAc 'SELECT 1'"
```

**Expect (failover needed):** C1 is not `running`, or the second command shows
`UNREACHABLE` / `FAILED` / no answer.

**If C1 is running and answers `1`:** C1 is fine. **Stop here, no failover.**
Fix the broken Vote server instead (restart it, check its logs).

```bash
echo "$(date -u +%T) confirmed: C1 is gone" >> ~/failover-times.txt
```

---

## 3. Fence C1: make sure it can't take writes

**Why:** if C1 came back on its own, its database would still believe it is the
primary. Two primaries means two different sets of votes that can't be merged
("split brain"). Stopping C1 prevents that.

**Do:**
```bash
# 1. look up C1's ID by its name and show it
C1_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=evgenia-voting-c1" \
  --query 'Reservations[].Instances[].InstanceId' --output text)
echo "$C1_ID"

# 2. stop C1 and wait until it is stopped
aws ec2 stop-instances --instance-ids "$C1_ID"
aws ec2 wait instance-stopped --instance-ids "$C1_ID"
echo "$(date -u +%T) C1 fenced (stopped)" >> ~/failover-times.txt
```

`C1_ID=$( … )` runs the command in brackets and keeps its output under the name
`C1_ID`; `"$C1_ID"` puts that value into the next commands.

**Expect:** `echo` shows one ID (`i-0…`). The `wait` returns without an error,
after up to a few minutes.

**If `echo` shows nothing or two IDs:** stop and look at the table from step 2.
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

**Expect:** `t|2026-…`. `t` = C2 is still a copy (good). The time is the last
change C2 received from C1; anything C1 saved after that moment is not on C2.
Write the time down.

**If `f`:** C2 is already a primary; someone promoted it. Skip to step 5.
**If UNREACHABLE:** C2 is not reachable either. Stop and investigate: there is
no copy to fail over to.

**Do, the promotion:**
```bash
ansible evgenia-voting-c2 -b -m command -a "docker exec voting-db-1 psql -U postgres -tAc 'SELECT pg_promote()'"
ansible evgenia-voting-c2 -b -m command -a "docker exec voting-db-1 psql -U postgres -tAc 'SELECT pg_is_in_recovery()'"
echo "$(date -u +%T) C2 promoted" >> ~/failover-times.txt
```

**Expect:** `t` (promotion done), then `f` (C2 is no longer a copy: it takes
writes).

**If the second answer is still `t`:** wait 10 seconds and ask again.
Promotion usually takes a few seconds.

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

Change the file, don't use `-var`: then a later `terraform apply` can't quietly
move the names back to C1.

```bash
cd ../terraform/infra
terraform plan
```

**Expect:** exactly **2 to change**: `db-write` and `db-read-a`, from
`10.0.20.68` (C1) to `10.0.21.196` (C2). Nothing to add, nothing to destroy.

**If the plan shows anything else:** stop and read it. Do not apply a plan you
don't understand.

```bash
terraform apply      # type yes
cd ../../ansible
echo "$(date -u +%T) db-write moved to C2" >> ~/failover-times.txt
```

Servers may remember the old address for up to 60 seconds (the record's TTL).

---

## 6. Check that votes are saved again

**Why:** proof that the failover worked, end to end.

**Do:**
```bash
# 1. does B2 see the new address?
ansible evgenia-voting-b2 -m command -a "getent hosts db-write.voting.internal"

# 2. is the queue in Redis b emptying? (repeat every few seconds)
ansible evgenia-voting-c2 -b -m command -a "docker exec voting-redis-1 redis-cli LLEN votes"
```

**Expect:** 1 shows `10.0.21.196`. 2 shows a number going down to `0`.

**If 1 still shows `10.0.20.68`:** wait a minute (TTL) and repeat.
**If 2 doesn't go down after 2 minutes:** look at the Worker logs on B2:
```bash
ansible evgenia-voting-b2 -b -m shell -a "docker logs --tail 20 \$(docker ps --filter name=worker -q | head -1)"
```

```bash
echo "$(date -u +%T) queue empty: votes are saved again" >> ~/failover-times.txt
```

Then open the results page: new votes appear again.

---

## 7. Record the new roles

**Why:** Ansible decides by `db_role` which server is the primary. It must match
reality, or a later playbook run could treat C1 as the primary again.

**Do:** swap the roles:

- `ansible/inventory/host_vars/evgenia-voting-c1.yml`: `db_role: replica`
- `ansible/inventory/host_vars/evgenia-voting-c2.yml`: `db_role: primary`

Commit this together with the `variables.tf` change:

```bash
cd ..
git add terraform/infra/variables.tf ansible/inventory/host_vars/
git commit -m "fix: fail over the database to C2"
cd ansible
```

**The outage is handled.** The rest can wait until zone a is back.

---

## Way back: when zone a returns

C2 stays the primary. C1 comes back as the new copy, so there is no second
switch and no second interruption.

### W1. Start zone a

```bash
# look up the three IDs by name and show them
A1_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=evgenia-voting-a1" --query 'Reservations[].Instances[].InstanceId' --output text)
B1_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=evgenia-voting-b1" --query 'Reservations[].Instances[].InstanceId' --output text)
C1_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=evgenia-voting-c1" --query 'Reservations[].Instances[].InstanceId' --output text)
echo "A1 $A1_ID  B1 $B1_ID  C1 $C1_ID"

aws ec2 start-instances --instance-ids "$A1_ID" "$B1_ID" "$C1_ID"
aws ec2 wait instance-running --instance-ids "$A1_ID" "$B1_ID" "$C1_ID"
echo "$(date -u +%T) zone a started" >> ~/failover-times.txt
```

C1's old database starts too and still believes it is the primary. That is safe
for now: nothing uses it, because all names point to C2. **Don't point anything
at C1.**

### W2. Let zone a's waiting votes drain

**Why:** votes that were waiting in Redis a when zone a went down are still on
C1's disk. B1's Worker saves them to `db-write`, which is now C2.

```bash
ansible evgenia-voting-c1 -b -m command -a "docker exec voting-redis-1 redis-cli LLEN votes"
```

**Expect:** goes down to `0` within a minute (repeat it).

### W3. Turn C1 into a copy of C2

**Why:** C1's old database must not come back as a primary. This deletes it and
copies C2's database instead. It runs only on the server with `db_role: replica`
(C1 after step 7), and only with `confirm=yes`.

```bash
ansible-playbook replica-init.yml -e confirm=yes
echo "$(date -u +%T) C1 is a copy again" >> ~/failover-times.txt
```

**Expect:** in the recap, C1 has several `changed`, C2 has `changed=0` (it only
checked its role and stopped), both `failed=0`.

### W4. Check

```bash
# C2 sends its changes to C1:  expect 10.0.20.68|streaming
ansible evgenia-voting-c2 -b -m command -a "docker exec voting-db-1 psql -U postgres -tAc 'SELECT client_addr, state FROM pg_stat_replication'"
# C1 is a copy:  expect t
ansible evgenia-voting-c1 -b -m command -a "docker exec voting-db-1 psql -U postgres -tAc 'SELECT pg_is_in_recovery()'"
# both hold the same votes:  expect the same number twice
ansible 'evgenia-voting-c*' -b -m command -a "docker exec voting-db-1 psql -U postgres -tAc 'SELECT COUNT(*) FROM votes'"
```

Both zones are back, with C2 as the primary and C1 as its copy.

Known limit: zone a now reads from C2 across zones (`db-read-a` follows the
primary). That works; pointing it back at C1 is an outlook item.