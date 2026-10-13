# Runbook: database failover to zone b

What to do when zone a fails and C1, the primary database, is gone.
Result: C2 becomes the primary, the name `db-write` points to it, and the
Worker saves the votes that waited in Redis b. No app changes and no lost votes.

Not automatic on purpose: promoting a database is the one step that can't be
undone, so a person decides. While I work, nothing is lost: new votes wait in
Redis b, and only the results page stops updating.

## Before you start

Run everything from the repo root in WSL. These helpers keep the commands short:

```bash
# instance ID by short name: id c1  ->  i-0...
id()   { aws ec2 describe-instances --filters "Name=tag:Name,Values=evgenia-voting-$1" \
           --query 'Reservations[].Instances[].InstanceId' --output text; }
# run SQL on a data server: sql c2 "SELECT 1"
sql()  { (cd ansible && ansible "evgenia-voting-$1" -b -o -m command \
           -a "docker exec voting-db-1 psql -U postgres -tAc \"$2\"" 2>/dev/null) | sed 's/.*(stdout) //'; }
# write down the time of each step, for the record afterwards
mark() { echo "$(date -u +%T) $*" | tee -a ~/failover-times.txt; }
```

## 1. Detect

Trigger: the email **"ALARM: evgenia-voting-vote-servers-down"** (fewer than 2
healthy Vote servers), or votes stop showing up on the results page.

```bash
mark "alarm email"
```

## 2. Confirm: is C1 really gone?

A failover is only for a lost primary database. If only a Vote server is down
and C1 is fine, fix that server instead, and stop here.

```bash
# which servers are running?
aws ec2 describe-instances --filters "Name=tag:Name,Values=evgenia-voting-*" \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value,State.Name]' --output table
# does the database on C1 answer? (1 = yes; nothing or UNREACHABLE = no)
sql c1 "SELECT 1"
```

Go on only if C1 is not running or its database does not answer.

```bash
mark "confirmed: C1 is gone"
```

## 3. Fence C1: make sure it can't take writes

If C1 came back by itself, its database would still believe it is the primary.
Two primaries means two different sets of votes. So stop it for good:

```bash
aws ec2 stop-instances --instance-ids $(id c1)
aws ec2 wait instance-stopped --instance-ids $(id c1)
mark "C1 fenced (stopped)"
```

If AWS can't stop it (the zone is unreachable), go on anyway. Step 5 moves
every app away from C1. Then never start C1 without following "Way back" below.

## 4. Promote C2

First check that C2 is a healthy copy and see how fresh it is:

```bash
sql c2 "SELECT pg_is_in_recovery(), pg_last_xact_replay_timestamp()"
```

`t` = still a copy (good). The timestamp is the last change it received from
C1. Anything C1 saved after that moment is missing on C2.

```bash
sql c2 "SELECT pg_promote()"            # t = promoted
sql c2 "SELECT pg_is_in_recovery()"     # f = C2 is now the primary and takes writes
mark "C2 promoted"
```

## 5. Move the names to C2

In `terraform/infra/variables.tf`, change the default of `db_primary` from
`"c1"` to `"c2"`. Edit the file, don't use `-var`, so a later `terraform apply`
can't quietly move the names back to C1.

```bash
cd terraform/infra
terraform plan     # must show exactly 2 changes: db-write and db-read-a, 10.0.20.68 -> 10.0.21.196
terraform apply
cd ../..
mark "db-write moved to C2"
```

Servers may remember the old address for up to 60 seconds (the record's TTL).

## 6. Check that votes are saved again

```bash
# B2 sees the new address (repeat until it shows 10.0.21.196)
(cd ansible && ansible evgenia-voting-b2 -o -m command -a "getent hosts db-write.voting.internal")
# the queue in Redis b empties (repeat until 0)
(cd ansible && ansible evgenia-voting-c2 -b -o -m command -a "docker exec voting-redis-1 redis-cli LLEN votes")
mark "queue empty: votes are saved again"
```

Then open the results page: new votes appear again.

## 7. Record the new roles

So that Ansible knows which server is which, swap the roles in the host vars:

- `ansible/inventory/host_vars/evgenia-voting-c1.yml`: `db_role: replica`
- `ansible/inventory/host_vars/evgenia-voting-c2.yml`: `db_role: primary`

Commit this together with the `variables.tf` change.

## Way back: when zone a returns

C2 stays the primary. C1 comes back as the new copy, so there is no second
switch and no second interruption.

1. Start zone a:

   ```bash
   aws ec2 start-instances --instance-ids $(id a1) $(id b1) $(id c1)
   aws ec2 wait instance-running --instance-ids $(id a1) $(id b1) $(id c1)
   mark "zone a started"
   ```

   C1's old database starts too, still believing it is the primary. Nothing
   uses it, because all names point to C2. Don't point anything at it.

2. Votes that waited in Redis a: B1's Worker saves them to `db-write`, which is
   now C2. Wait until the queue on C1 is empty:

   ```bash
   (cd ansible && ansible evgenia-voting-c1 -b -o -m command -a "docker exec voting-redis-1 redis-cli LLEN votes")
   ```

3. Turn C1 into a copy of C2. This deletes C1's old database and copies C2's:

   ```bash
   cd ansible
   ansible-playbook replica-init.yml -e confirm=yes
   cd ..
   mark "C1 is a copy again"
   ```

4. Check:

   ```bash
   sql c2 "SELECT client_addr, state FROM pg_stat_replication"   # 10.0.20.68 | streaming
   sql c1 "SELECT pg_is_in_recovery()"                           # t
   sql c1 "SELECT COUNT(*) FROM votes"; sql c2 "SELECT COUNT(*) FROM votes"   # equal
   ```

Known limit: zone a now reads from C2 across zones (`db-read-a` follows the
primary). That works; pointing it back at C1 is an outlook item.