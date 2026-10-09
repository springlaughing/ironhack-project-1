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

- **type:** `feat` new behavior · `fix` bug fix · `refactor` same behavior, cleaner code · `docs` · `test` · `build` Dockerfiles and images · `ci` pipelines · `chore` housekeeping
- **scope:** `worker` · `vote` · `result` · `compose` · `terraform` · `ansible`
- **description:** imperative, lower case, under 72 characters, no period

The body explains **why**, not what. Link the issue in the last line.

```
fix(worker): save votes with one upsert so retries can't double-count

The votes table had no uniqueness rule, so one voter was counted
once per click (experiment 1: 6 rows for one voter).

Closes #1
```

### Commit template

```bash
cat > ~/.gitmessage <<'EOF'
# type(scope): short description, under 72 characters
# types: feat fix refactor docs test build ci chore
# scopes: worker vote result compose terraform ansible

# Why this change? (optional, wrap at 72 characters)

# Closes #
EOF
git config --global commit.template ~/.gitmessage
git config --global core.editor nano
```

Then commit with `git commit` (without `-m`) to get the template.

## Secrets

Never commit passwords, keys, `.env` files, `*.tfvars` or Terraform state.
`.gitignore` blocks the usual ones. A secret that was pushed once stays in
the history: change the secret, don't just delete the file.