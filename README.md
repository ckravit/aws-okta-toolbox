# aws-okta-toolbox

A lightweight, portable toolkit for authenticating with AWS via Okta and
connecting to cloud resources — without requiring local admin rights beyond
a one-time container runtime install. All AWS tooling runs inside a Docker
container, making it consistent across Mac and Windows regardless of what
is installed locally.

## What's included

| Tool | Purpose |
|---|---|
| `okta-aws-cli` | Okta browser-based auth → writes temp AWS credentials to `~/.aws` |
| AWS CLI v2 | AWS API access and SSM session management |
| Session Manager Plugin | SSM tunnel engine for port forwarding and SSH |
| `ssh` client | Used by VSCode Remote SSH and terminal SSH via SSM |
| `nano` | Lightweight in-container text editor |

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Installation](#installation)
3. [Configuration](#configuration)
4. [Authentication](#authentication)
5. [Connections](#connections)
   - [SSH Terminal](#ssh-terminal)
   - [VSCode Remote SSH](#vscode-remote-ssh)
   - [Jupyter Notebook / Lab](#jupyter-notebook--lab)
   - [Database on EC2](#database-on-ec2)
   - [S3 and General AWS Commands](#s3-and-general-aws-commands)
6. [Updating Tool Versions](#updating-tool-versions)
7. [Versioning and Releases](#versioning-and-releases)
8. [Platform Notes](#platform-notes)

---

## Prerequisites

The following must be in place before using this toolbox.

### Container runtime

Install one — you do not need both.

**Option A — Docker Desktop** (Mac and Windows):
- Mac: https://docs.docker.com/desktop/install/mac-install/
- Windows: https://docs.docker.com/desktop/install/windows-install/

**Option B — Colima** (Mac only, via Homebrew):

```bash
brew install colima docker 
colima start
```

See [Platform Notes](#platform-notes) for Colima configuration details.

### Okta credentials

You will need two values from your Okta/AWS admin before you can authenticate:

- `OKTA_ORG_DOMAIN` — e.g. `mycompany.okta.com`
- `OKTA_OIDC_CLIENT_ID` — e.g. `0oa1b2c3d4e5f6g7h8i9`

---

## Installation

### 1. Get the toolbox

Clone the repository or unzip the provided archive into a folder of your
choice. All steps below assume you are inside that folder.

### 2. Build the Docker image

```bash
docker build -t aws-okta-toolbox .
```

This must be run from inside the toolbox folder. It only needs to be re-run
when you update tool versions in the Dockerfile.

### 3. Make scripts executable (Mac / Linux / Git Bash / WSL)

```bash
chmod +x okta-auth.sh awstunnel.sh awsdo.sh
```

### 4. Add scripts to your PATH

This lets you run the scripts from any directory. 
_(Make sure you change `/path/to/` to the appropriate path on your computer)_

**Mac / Linux**: add to `~/.zshrc` or `~/.bashrc`: \
**Windows (Git Bash / WSL)**: add to `~/.bashrc`:

```bash
export PATH="$PATH:/path/to/aws-okta-toolbox"
```

Reload your shell after editing:

```bash
source ~/.zshrc   # or source ~/.bashrc
```

**Windows (PowerShell)** — add to your PowerShell profile (`notepad $PROFILE`):

```powershell
$env:PATH += ";C:\path\to\aws-okta-toolbox"
```
_Windows note_: Use the `.ps1` versions of all scripts: `okta-auth.ps1`, `awstunnel.ps1`,
`awsdo.ps1`.


---
<!--
Source - https://stackoverflow.com/a/16426829
Posted by uberllama, modified by community. See post 'Timeline' for change history
Retrieved 2026-03-25, License - CC BY-SA 4.0
-->

## Configuration

Configurations live in two files in the `config/` folder. Copy each example
file (or edit) and remove the `.example` extension, and fill in your values.

Config files: 
* `config/aws-okta-toolbox.env.example` - Environment variables
* `config/aws-okta-toolbox.conf.example` - SSH Configurations

### aws-okta-toolbox.env

Contains your Okta credentials, AWS region, and instance IDs / connection
targets. 

**Step 1 — Fill in your values:**

Open `config/aws-okta-toolbox.env` and set at minimum these settings.  
_(Add instance IDs and connection targets as needed for your environment)_:

```bash
export OKTA_ORG_DOMAIN="mycompany.okta.com"
export OKTA_OIDC_CLIENT_ID="0oa1b2c3d4e5f6g7h8i9"
```

**Step 2 — Add to your shell profile so it loads automatically:** _(Make sure you change `/path/to/` to the appropriate path on your computer)_  
**Mac / Linux**: add to `~/.zshrc` or `~/.bashrc`: \
**Windows (Git Bash / WSL)**: add to `~/.bashrc`:
```bash
source /path/to/aws-okta-toolbox/config/aws-okta-toolbox.env
```

**Step 3 - Reload your shell after editing**
```bash
source ~/.zshrc   # or source ~/.bashrc
```

**Env Updates -** If you make changes to the env file later, re-source it (Step 3) for the changes to
take effect in your current session.


### aws-okta-toolbox.conf
Used for SSH connections only.
Contains SSH host definitions for your remote instances. Fill in your
instance IDs, usernames, key paths, and the full path to `ssm-proxy.sh`.  

Move the filled-in file to your SSH directory:

```bash
mv config/aws-okta-toolbox.conf ~/.ssh/aws-okta-toolbox.conf
```

Then add one line to the **top** of your `~/.ssh/config`.  
_On Mac/Linux:_
```
Include ~/.ssh/aws-okta-toolbox.conf
```

_On Windows (OpenSSH):_

```
Include %USERPROFILE%\.ssh\aws-okta-toolbox.conf
```

No reload is needed — SSH reads the file on every connection.

---

## Authentication

**`okta-auth.sh` is the single script for all authentication**  
> [!IMPORTANT]  
> **You MUST run this to first login or refresh an expired session**

```bash
# Mac / Linux / Git Bash
okta-auth
```
```bash
# Windows PowerShell
okta-auth.ps1
```

**What happens:**
1. A URL and one-time code are printed in the terminal
2. Open the URL in your browser, approve the Okta request, and login normally
3. Return to the terminal and select your AWS account and role from the list using the keyboard to navigate.
4. Temporary credentials are automatically written to `~/.aws/credentials` and the container exits

**When to run it:**
- First thing before you start working to create an authenticated session
- Any time you see an authentication or credentials error
  - `awstunnel` and `awsdo` will explicitly tell you when your session has
  expired and prompt you to re-run `okta-auth`

---

## Connections

### SSH Terminal

**Prerequisites:**

- **SSH key pair** — your public key must be in `~/.ssh/authorized_keys` on
  the remote instance/server, and your private key must be
  referenced in `IdentityFile` in `aws-okta-toolbox.conf`.  
  Check out [this doc](https://tinyurl.com/sshkeycreateguide) for info on creating an SSH Keypair
- `aws-okta-toolbox.conf` configured and included in the `~/.ssh/config` _(see above [Configuration](#aws-okta-toolboxconf))_

1. Authenticate:
   ```bash
   okta-auth
   ```
2. SSH to the server (`my-server` is the `Host` name defined in `aws-okta-toolbox.conf`):
   ```bash
   ssh my-server
   ``` 

#### Troubleshooting SSH

**"percent_expand: failed" or "unknown key %d"**
You have an old inline `docker run` ProxyCommand using `%d` in your
`~/.ssh/aws-okta-toolbox.conf`. Replace it with the script-based ProxyCommand as shown in the example file.

**"Host key verification failed"**
Add `StrictHostKeyChecking no` to the host block — instance IDs change when
instances are replaced.

**"Permission denied (publickey)"**
- Is your private key path correct in `IdentityFile` of `~/.ssh/aws-okta-toolbox.conf`?
- Has your public key been added to `~/.ssh/authorized_keys` on the instance?
- Did you follow the [Configuration](#aws-okta-toolboxconf) above?  

**Connection hangs after Okta URL**
Your SSM session token expired mid-connect. Re-run `okta-auth` and try again.

If still having trouble, contact your admin.

---

### VSCode Remote SSH

**Prerequisites:** 
- Same as [SSH Terminal](#ssh-terminal): SSH key pair and
`aws-okta-toolbox.conf` configured. 
- VSCode with the
[Remote - SSH](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh)
extension installed.

1. Authenticate:
   ```bash
   okta-auth
   ```
2. Open VSCode
3. Open the Remote Explorer panel (or `Cmd+Shift+P` → "Remote-SSH: Connect to Host")
4. Your hosts from `aws-okta-toolbox.conf` appear in the list
5. Click to connect

If VSCode times out on first connect, add `ConnectTimeout 30` to the host
block in `aws-okta-toolbox.conf`.

> **Note:** VSCode must be restarted if Docker or Colima was installed while
> it was open. VSCode inherits PATH at launch time.

---

### Jupyter Notebook / Lab

**Use case:** Connect your local browser to a Jupyter server running on an
EC2 instance. The instance runs Jupyter in Docker with a locally exposed port
(`8888:8888`). SSM port forwarding creates a tunnel from your machine to that
port without requiring a public IP or open firewall rules.

**Prerequisites:**
- EC2 instance with Docker installed
- Jupyter running on the instance: `docker run -d -p 8888:8888 jupyter/base-notebook`
- Instance ID set as `JUPYTER_INSTANCE` in your env file

**Steps:**

1. Authenticate:
   ```bash
   okta-auth
   ```

2. Start the tunnel:   
_Jupyter awstunnel syntax `awstunnel jupyter <instance ID>`_
   ```bash
   awstunnel jupyter $JUPYTER_INSTANCE
   ```
   
   or with an explicit instance ID:
   ```bash
   awstunnel jupyter i-0abc1234567890def
   ```

3. Open your browser to **http://localhost:8888**

4. Enter the token or password configured on the Jupyter server

Press `Ctrl-C` in the terminal to close the tunnel when done.

---

### Database on EC2

**Use case:** Connect to a database running directly on an EC2 instance in a Docker container (e.g. MySQL or Postgres). The database and the SSM tunnel endpoint are on the same instance — so the remote host is `localhost` on that instance.

```
Your machine → SSM → EC2 instance (DB running here on localhost)
```

**Prerequisites:**
- EC2 instance with Docker installed and the database container running with
  a locally exposed port:
  ```bash
  # MySQL example
  docker run -d -p 3306:3306 --name demo-mysql -e MYSQL_ROOT_PASSWORD=changemepaassword mysql
  ```
  ```bash
  # Postgres example
  docker run -d -p 5432:5432 --name demo-pg -e POSTGRES_PASSWORD=changemepaassword postgres
  ```
- Instance ID set in your `aws-okta-toolbox.env` file

**Steps:**

1. Authenticate:
   ```bash
   okta-auth
   ```

2. Start the tunnel — remote host is `localhost` (the DB is on the instance):   
_Database tunnel syntax `awstunnel db <instance ID> <remote host> <port#>`_
   ```bash
   # MySQL
   awstunnel db i-0abc1234567890def localhost 3306
   ```
   ```bash
   # Postgres
   awstunnel db i-0abc1234567890def localhost 5432
   ```

3. In your database client (SQL Developer Toolkit, DBeaver, etc), connect to:
   - **Host:** `localhost`
   - **Port:** `3306` or `5432` (or other custom port)
   - **Username / Password:** credentials configured on the database container

Press `Ctrl-C` in your command-line interface to close the tunnel when done.

---

### S3 and General AWS Commands

**Use case:** Run any AWS CLI command — S3 operations, EC2 queries, Secrets
Manager, and more — without installing the AWS CLI locally. Your current
directory is automatically mounted into the container so local files are
accessible.

```bash
# Mac / Linux / Git Bash
awsdo <aws command>
```
```bash
# Windows PowerShell
awsdo.ps1 <aws command>
```

#### Create a non-Okta AWS profile (static keys)

For AWS access that uses static keys rather than Okta (e.g. with access keys specific for S3), configure a named profile inside the container:

```bash
awsdo aws configure --profile s3-work
```

This writes to `~/.aws/credentials` and `~/.aws/config` on your host via the
mount, so the profile persists across container runs. Use it with:

```bash
awsdo aws s3 ls --profile s3-work
```
or set the `AWS_PROFILE` environment variable  
_one-time use:_
```bash
AWS_PROFILE=s3-work awsdo aws s3 ls
```
_export it for whole session - good when expecting to run multiple commands (recommended):_
```bash
export AWS_PROFILE=s3-work 
awsdo aws s3 ls
awsdo aws s3 ls s3://my-bucket/
```

#### Directories / Mount Paths
Your _current directory_ is mounted as `/work` inside the toolkit container by default.  In the below `/work/file.csv` is actually using the toolkit container's mounted path `/work`  to reference the local `file.csv`

```bash
# Use current directory (default)
cd ~/my-data
awsdo aws s3 cp /work/file.csv s3://my-bucket/uploads/
```
To use a different path — such as a network drive — set the `AWSDO_MOUNT_DIR` environment variable:  
_one-time use:_
```bash
AWSDO_MOUNT_DIR="/Volumes/network-drive/data" awsdo aws s3 cp /work/file.csv s3://my-bucket/uploads/
```
_export it for whole session - good when expecting to run multiple commands (recommended):_
```bash
export AWSDO_MOUNT_DIR="/Volumes/network-drive/data"
awsdo aws s3 cp /work/file.csv s3://my-bucket/data/
awsdo aws s3 ls s3://my-bucket/data/
```

#### S3 examples

```bash
# List all buckets
awsdo aws s3 ls

# List contents of a bucket
awsdo aws s3 ls s3://my-bucket/some/prefix/

# Copy a local file up to S3
cd ~/my-data   # or set AWSDO_MOUNT_DIR
awsdo aws s3 cp /work/file.csv s3://my-bucket/uploads/

# Copy a file from S3 down to your local directory
awsdo aws s3 cp s3://my-bucket/data/file.csv /work/file.csv

# Sync a local folder up to S3
awsdo aws s3 sync /work s3://my-bucket/data/

# Sync from S3 down to your local directory
awsdo aws s3 sync s3://my-bucket/data/ /work
```

#### EC2 and SSM examples

```bash
# List running instances (useful for finding instance IDs)
awsdo aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query "Reservations[*].Instances[*].{ID:InstanceId,Name:Tags[?Key=='Name']|[0].Value}" \
  --output table

# List SSM-reachable instances
awsdo aws ssm describe-instance-information \
  --query "InstanceInformationList[*].{ID:InstanceId,Ping:PingStatus}" \
  --output table
```

#### Interactive shell

For running multiple commands without spinning up a new container each time:

```bash
awsdo bash
```

Inside the container, `aws` is a normal command and `/work` is your current
directory on the host.

---

## Updating Tool Versions

Versions are controlled by `ARG` lines at the top of the `Dockerfile`.
To pin or bump a tool, edit the relevant line and rebuild:

```dockerfile
ARG OKTA_AWS_CLI_VERSION=2.4.1    # pin to a specific release
ARG AWS_CLI_VERSION=2.19.43       # pin AWS CLI
ARG SSM_PLUGIN_VERSION=latest     # or leave as latest
```

Then rebuild:

```bash
docker build -t aws-okta-toolbox .
```

Release pages:
- okta-aws-cli: https://github.com/okta/okta-aws-cli/releases
- AWS CLI v2: https://raw.githubusercontent.com/aws/aws-cli/v2/CHANGELOG.rst
- SSM Plugin: https://docs.aws.amazon.com/systems-manager/latest/userguide/plugin-version-history.html

---

## Versioning and Releases

The current version is in the `VERSION` file at the root of the repo and
matches the latest git tag.

### Cutting a release

After committing your changes:

```bash
# Update the version number
echo "1.0.1" > VERSION
git add VERSION
git commit -m "Release v1.0.1"

# Tag and push
git tag -a v1.0.1 -m "v1.0.1"
git push origin main --tags
```

Use semantic versioning:
- **PATCH** (`1.0.0` → `1.0.1`) — bug fixes, tool version bumps in Dockerfile
- **MINOR** (`1.0.0` → `1.1.0`) — new scripts or features
- **MAJOR** (`1.0.0` → `2.0.0`) — breaking changes

### Rolling back

If something breaks after a pull:

```bash
git checkout v1.0.0
docker build -t aws-okta-toolbox .
```

To see all available tags:

```bash
git tag
```

---

## Platform Notes

### macOS

Works with Docker Desktop or Colima. Scripts are tested on zsh (default
macOS shell) and bash.

### Colima (macOS)

Colima works with this toolbox as-is. To verify it is running native ARM
on Apple Silicon:

```bash
colima status
```

Look for `arch: aarch64` — that is correct for Apple Silicon.

**Optional: switch to the faster VZ runtime (macOS 13 Ventura+ only):**

```bash
colima stop
colima start --vm-type=vz --vz-rosetta --mount-type virtiofs
```

Or use `colima start --edit` to change the config in an editor before
starting to set any desired defaults. 

### Windows (PowerShell)

Use the `.ps1` versions of all scripts: `okta-auth.ps1`, `awstunnel.ps1`,
`awsdo.ps1`.

Add the toolbox folder to PATH via your PowerShell profile (`notepad $PROFILE`):

```powershell
$env:PATH += ";C:\path\to\aws-okta-toolbox"
```

For SSH config, the Include directive uses `%USERPROFILE%`:

```
Include %USERPROFILE%\.ssh\aws-okta-toolbox.conf
```

### Windows (Git Bash / WSL)

Use the `.sh` scripts. Make them executable after unzipping:

```bash
chmod +x okta-auth.sh awstunnel.sh awsdo.sh
```

---

## File Reference

```
aws-okta-toolbox/
├── Dockerfile                        Image — edit ARG lines to change versions
├── VERSION                           Current version number
├── okta-auth.sh / okta-auth.ps1      Authenticate / refresh session
├── awstunnel.sh / awstunnel.ps1            Start SSM tunnels
├── awsdo.sh / awsdo.ps1              Run any AWS CLI command
├── config/
│   ├── aws-okta-toolbox.env.example  Copy, fill in, and source this
│   └── aws-okta-toolbox.conf.example Copy, fill in, and add Include to ~/.ssh/config
└── scripts/
    ├── entrypoint.sh                 Container entrypoint
    └── ssm-proxy.sh                  SSH ProxyCommand helper
```
