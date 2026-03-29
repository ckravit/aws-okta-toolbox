#!/bin/bash
# ssm-proxy.sh — SSH ProxyCommand for SSM tunnels

set -u

INSTANCE_ID="$1"
PORT="${2:-22}"
PROFILE="${AWS_PROFILE:-default}"
REGION="${AWS_DEFAULT_REGION:-us-west-2}"
IMAGE="${AWS_OKTA_TOOLBOX_IMAGE:-aws-okta-toolbox}"

# Ensure docker is found (especially for VS Code / GUI SSH launches)
export PATH="/usr/local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/c/Program Files/Docker/Docker/resources/bin:$PATH"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found in PATH" >&2
  exit 1
fi

# Detect Git Bash / Windows
if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* || "$OSTYPE" == win32* ]]; then
  if [[ -z "${USERPROFILE:-}" ]]; then
    echo "USERPROFILE not set" >&2
    exit 1
  fi

  AWS_DIR_MOUNT="$(cygpath -w "$USERPROFILE")\\.aws"

  if [[ ! -d "$USERPROFILE/.aws" && ! -d "$USERPROFILE\\.aws" ]]; then
    echo "AWS credentials directory not found: $USERPROFILE\\.aws" >&2
    exit 1
  fi

  exec env MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*" docker run --rm -i \
    -v "${AWS_DIR_MOUNT}:/root/.aws" \
    -e AWS_PROFILE="$PROFILE" \
    -e AWS_DEFAULT_REGION="$REGION" \
    "$IMAGE" \
    aws ssm start-session \
      --region "$REGION" \
      --profile "$PROFILE" \
      --target "$INSTANCE_ID" \
      --document-name AWS-StartSSHSession \
      --parameters "portNumber=${PORT}"

else
  AWS_DIR_MOUNT="$HOME/.aws"

  if [[ ! -d "$AWS_DIR_MOUNT" ]]; then
    echo "AWS credentials directory not found: $AWS_DIR_MOUNT" >&2
    exit 1
  fi

  exec docker run --rm -i \
    -v "${AWS_DIR_MOUNT}:/root/.aws" \
    -e AWS_PROFILE="$PROFILE" \
    -e AWS_DEFAULT_REGION="$REGION" \
    "$IMAGE" \
    aws ssm start-session \
      --region "$REGION" \
      --profile "$PROFILE" \
      --target "$INSTANCE_ID" \
      --document-name AWS-StartSSHSession \
      --parameters "portNumber=${PORT}"
fi