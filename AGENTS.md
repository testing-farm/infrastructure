# Working in this repository

⚠️ **This repository contains secrets. Be extremely careful — treat every
change as a potential secret leak until you have confirmed it is not.**

## Secret footprint

Encrypted at rest (ansible-vault — committed, must stay encrypted):

- `ansible/secrets/credentials.yaml` — primary credentials store
- `ansible/secrets/certs/**/*.pem.vault` — TLS cert/key material
- `ansible/secrets/ssh/id_rsa_*` — SSH private keys
- `ansible/secrets/quay/*.json` — Quay registry auth

Plaintext/backup variants of these (`.vault_pass`, `*.decrypted`, `*.bak`, …)
are kept out of git by `.gitignore` — never force-add them.

## Hard rules

1. **Never** use `git add -A`, `git add -a`, or `git add .`. Stage files
   explicitly. Use `git add -u` plus explicit paths for already-tracked files.
2. **Never** skip pre-commit and **never** commit with `--no-verify` / `-n`.
   The gitleaks check must run on every commit — no exceptions.
3. If you are **unsure** whether a change may contain a secret, STOP and ask the
   user for permission before staging or committing it.
4. Secrets at rest must stay ansible-vault encrypted. Never commit a decrypted
   copy or a suffixed backup of a secret file, and never `git add -f` a
   gitignored secret artifact.

## Setup

Run `direnv allow` in the repo root. It enforces that `pre-commit` is installed
and installs the git hook automatically (install pre-commit with
`sudo dnf install -y pre-commit` if missing).
