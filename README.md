# CQT-deployer

Ansible automation for CQT deployment (reporting and experiments). The first implemented target is
`CQT-reporting`, which bootstraps the reporting host, deploys
[`Scinawa/CQT-reporting`](https://github.com/Scinawa/CQT-reporting), and installs
a daily scheduled runner with Telegram notifications.

## Repository Layout

```text
CQT-deployer/
├── ansible.cfg
├── inventory/
│   ├── host_vars/
│   │   └── cqt-reporting/
│   │       └── vault.yml
│   └── hosts.yml
├── playbooks/
│   └── cqt-reporting.yml
└── roles/
    └── cqt_reporting/
```

## What The `cqt_reporting` Role Does

- installs the system packages required by `CQT-reporting`, including LaTeX,
  Git, Python, and `uv`
- creates the host users `elis`, `cqt-deploy`, and `sergi`
- grants sudo through `/etc/sudoers.d/cqt-reporting-admins` to `ubuntu`,
  `elis`, and `sergi`, while keeping `cqt-deploy` out of sudo
- clones `git@github.com:Scinawa/CQT-reporting.git` into `/opt/cqt-reporting`
  as `cqt-deploy`
- generates a GitHub deploy key for `cqt-deploy` and pauses on the first run so
  the key can be added to the repository
- installs a daily cron job at `16:00` that runs a Python wrapper script as
  `cqt-deploy`
- has the wrapper pull the repo, sync the Python environment, check whether the
  latest or best remote run changed, generate reports only when new data exists,
  publish the generated `report.pdf` to the repository `gh-pages` branch, and
  send the outcome to Telegram

The role creates the user accounts, but it does not manage login SSH keys for
`elis` or `sergi`.

## Configuration

Shared, non-secret configuration lives in
`roles/cqt_reporting/defaults/main.yml`.

Only the Telegram secrets live in the vaulted host vars file:

- `inventory/host_vars/cqt-reporting/vault.yml`

The checked-in vault currently contains placeholder `CHANGE_ME` values so the
repo has the right structure without storing real secrets in plain text.

Before the first deployment:

1. Edit `inventory/host_vars/cqt-reporting/vault.yml` with `ansible-vault edit`.
2. Replace both placeholder values with the real Telegram bot token and chat ID.
3. Rekey the vault if you do not want to keep the temporary placeholder password.

The current temporary vault password for the sample file is `change-me`.

If you need host-specific non-secret overrides later, add
`inventory/host_vars/cqt-reporting/main.yml`. Common candidates are:

- `cqt_reporting_repo_version`
- `cqt_reporting_git_commit_name`
- `cqt_reporting_git_commit_email`
- `cqt_reporting_report_command`
- `cqt_reporting_report_environment`
- `cqt_reporting_publish_branch`
- `cqt_reporting_publish_target_path`

The default report command is:

```yaml
cqt_reporting_report_command:
  - bash
  - scripts/report.sh
  - best-latest-pdf
```

If you want the scheduled flow to generate a different report flavor later, this
is the variable to change.

By default the role also sets:

```yaml
cqt_reporting_report_environment:
  SHOW_ERRORS: "true"
```

This is a deployment-side workaround for the current upstream `report.sh`
behavior, which emits `--no-show-errors` even though `src/main.py` only accepts
`--show-errors`.

The runner treats these generated files as disposable tracked artifacts and may
restore them in the main checkout when they are the only tracked local changes:

- `report.tex`
- `report.pdf`
- `reports/latest_report.pdf`

Timestamped archive PDFs under `reports/report_*.pdf` are left untracked on the
server and are not part of the automated publish step.

The production artifact is published separately to the `gh-pages` branch, where
`index.html` can display the root-level `report.pdf`.

## SSH Prerequisite

The inventory targets the local SSH config alias `cqt-reporting`, so the control
machine must have an entry like:

```sshconfig
Host cqt-reporting
    User ubuntu
    HostName 54.251.1.211
    Port 22
    IdentityFile ~/.ssh/scinawa-cqt.pem
    ForwardAgent yes
```

## First Deployment

Run:

```bash
ansible-playbook --ask-vault-pass playbooks/cqt-reporting.yml
```

On the first run the playbook will print the generated public key for
`cqt-deploy` and pause. Add that key as a deploy key with write access at:

- `https://github.com/Scinawa/CQT-reporting/settings/keys`

Then continue the playbook.

If `/opt/cqt-reporting` already existed from an earlier manual clone or a failed
run, rerun the playbook. The role now recursively resets the checkout ownership
to `cqt-deploy` before the Git step so Git does not fail with a dubious
ownership error.

If `/opt/cqt-reporting/.git` already exists, the playbook skips the Ansible
clone step entirely. After the first bootstrap, repository updates are handled
by the installed runner on the server rather than by subsequent playbook runs.

## Installed Runtime Paths

- project checkout: `/opt/cqt-reporting`
- runner script: `/usr/local/lib/cqt-reporting/cqt_reporting_runner.py`
- runner config: `/etc/cqt-reporting/runner.json`
- runner state: `/var/lib/cqt-reporting/state.json`
- runner log: `/var/log/cqt-reporting/runner.log`

## Manual Verification

After deployment, you can test the scheduled runner manually on the target host:

```bash
sudo -u cqt-deploy /opt/cqt-reporting/.venv/bin/python   /usr/local/lib/cqt-reporting/cqt_reporting_runner.py   --config /etc/cqt-reporting/runner.json   --force
```

That uses the same path as cron, but forces a run even if the stored state says
there is no new data yet.
