# Contributing

How work is organized in this repository.

## Workflow

1. Every change starts from an issue. Pick one, or create it first.
2. Create a branch linked to the issue:
   ```bash
   gh issue develop <number> --checkout
   ```
   Or by hand, named after the issue: `step1-worker-upsert`.
3. Make small commits, one logical change each (format below).
4. Test before opening a pull request:
   - `docker compose up -d` starts cleanly
   - the experiments related to the change pass
5. Open a pull request to `main` with `Closes #<number>` in the description.
   Merging closes the issue.

`main` must always work. Nothing is committed to it directly.

## Branch names

`<step>-<part>-<short-topic>`, for example:

| Branch | Issue |
| --- | --- |
| `step1-worker-upsert` | Worker: UNIQUE rule and one-step upsert |
| `step1-compose-reliability` | Compose: restart policies, Redis durability |
| `step2-terraform-network` | Terraform: network for both zones |

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/): `type(scope): description`

- **description:** imperative ("add", not "added"), lower case, under 72
  characters, no period

### Type: what kind of change?

| Type | Use it when | Ask yourself | Example from this project |
| --- | --- | --- | --- |
| `feat` | The app or the infrastructure can do something it couldn't before | "Is there something new a user or operator can see or use?" | `feat(vote): add health check that also tests Redis` |
| `fix` | Something worked wrong and now works right | "Was this a bug, or did an experiment prove it broken?" | `fix(worker): save votes with one upsert so retries can't double-count` |
| `refactor` | The code is cleaner, but the behavior is exactly the same | "Would a user notice any difference? No → refactor" | `refactor(worker): move vote saving into its own method` |
| `perf` | Same behavior, but faster or uses less | "Is the only goal speed or resources?" | `perf(worker): wait with BLMOVE instead of polling every 100 ms` |
| `docs` | Only text for humans: README, guides, comments, runbooks | "Does no code or config change?" | `docs: add failover runbook` |
| `test` | Load tests, experiment scripts, test data | "Does this only check things, without changing them?" | `test: add k6 script for 2,000 votes in 5 seconds` |
| `build` | How images are built: Dockerfiles, `build.sh`, dependencies | "Does it change what goes into an image?" | `build(result): pin Node to version 20 in the Dockerfile` |
| `ci` | Automatic pipelines (GitHub Actions) | "Does it change something that runs on GitHub?" | `ci: build and scan images on every merge` |
| `chore` | Housekeeping that changes no behavior | "Is it tidying: `.gitignore`, renames, tool settings?" | `chore: ignore Terraform state files` |

### Scope: which part of the project?

The scope is the folder or component you changed. Leave it out when the
change spans the whole project: `docs: add contributing guide`.

| Scope | Covers | Example |
| --- | --- | --- |
| `vote` | `vote/`: the Flask voting page | `fix(vote): show an error when Redis is down` |
| `result` | `result/`: the Node results page | `fix(result): reconnect after a database restart` |
| `worker` | `worker/`: the .NET Worker | `feat(worker): finish current vote on shutdown signal` |
| `compose` | `docker-compose.yml`, `.env.example` | `feat(compose): run three Worker containers` |
| `terraform` | `terraform/`: AWS resources | `feat(terraform): add load balancer with path rules` |
| `ansible` | `ansible/`: installing and starting on servers | `feat(ansible): deploy Workers to B1` |
| `db` | Database tables, rules, replication setup | `fix(db): add unique rule on voter id` |
| `redis` | Redis settings | `feat(redis): turn on the append-only file` |

### Tricky cases

| Situation | Choose | Why |
| --- | --- | --- |
| Restart policies were missing, experiment 2 lost votes | `fix(compose)` | It was proven broken; now it isn't |
| Removing the password from the logs | `fix(worker)` | A security bug is still a bug |
| Moving a hard-coded host name into an environment variable | `refactor(worker)` | Same behavior, more flexible code |
| Same change, but now the app can run on AWS where it couldn't before | `feat(worker)` | Pick by what it enables, if that is the point |
| Adding Worker replicas | `feat(compose)` | New capability: several Workers |
| First version of the Terraform network | `feat(terraform)` | New infrastructure is new behavior |
| Fixing a typo in a comment inside `worker/` | `docs(worker)` | Only text for humans changed |
| One commit needs two types | Split it into two commits | One commit, one reason |

When in doubt between two types, pick the one that answers "why would
someone read this commit later?". If you still can't decide, the commit
probably does two things: split it.

The body explains **why**, not what. Link the issue in the last line.

```
fix(worker): save votes with one upsert so retries can't double-count

The votes table had no uniqueness rule, so one voter was counted
once per click (experiment 1: 6 rows for one voter).

Closes #1
```

### Commit template

The template is in the repository as `.gitmessage`, so every computer gets
the same version with `git pull`. Git doesn't use it automatically: turn it
on once per clone, from the project folder:

```bash
git config commit.template .gitmessage
git config core.editor nano
```

Settings made with `git config` (without `--global`) apply to this
repository only and are not committed, so repeat this on every computer.

Then commit with `git commit` (without `-m`): nano opens with the template.
Lines starting with `#` are hints and are left out of the message.

## Secrets

Never commit passwords, keys, `.env` files, `*.tfvars` or Terraform state.
`.gitignore` blocks the usual ones. A secret that was pushed once stays in
the history: change the secret, don't just delete the file.