#!/bin/bash
# awsdo.sh
# Run any AWS CLI command inside the container without dealing with docker run
# boilerplate. Your current directory is mounted by default so local files
# are accessible inside the container at /work.
#
# Usage:
#   awsdo aws s3 ls
#   awsdo aws s3 cp /work/file.csv s3://my-bucket/uploads/
#   awsdo aws ec2 describe-instances --output table
#   awsdo bash                          # drop into an interactive shell
#
# Mount a different local directory:
#   AWSDO_MOUNT_DIR="/path/to/data" awsdo aws s3 cp /work/file.csv s3://bucket/
#
# Or export it for the session:
#   export AWSDO_MOUNT_DIR="/path/to/data"
#   awsdo aws s3 sync /work s3://my-bucket/data/
#
# Tip: if you need to run many commands in a row, "awsdo bash" is more
# efficient than spinning up a new container for each command.

set -euo pipefail

PROFILE="${AWS_PROFILE:-default}"
REGION="${AWS_DEFAULT_REGION:-us-west-2}"
IMAGE="aws-okta-toolbox"

# Defaults to current directory unless overridden
MOUNT_DIR="${AWSDO_MOUNT_DIR:-$PWD}"

# Detect Windows Git Bash / MSYS / Cygwin
if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* || "$OSTYPE" == win32* ]]; then
  if [[ -z "${USERPROFILE:-}" ]]; then
    echo "❌ USERPROFILE is not set. Cannot determine Windows home directory."
    exit 1
  fi

  # For normal shell commands in Git Bash
  AWS_DIR_CREATE="$(cygpath -u "$USERPROFILE")/.aws"

  # For docker.exe bind mounts
  AWS_DIR_MOUNT="$(cygpath -w "$USERPROFILE")\\.aws"
  WORK_DIR_MOUNT="$(cygpath -w "$MOUNT_DIR")"

  mkdir -p "$AWS_DIR_CREATE"

  # Credential check
  if ! MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*" docker run --rm \
      -v "${AWS_DIR_MOUNT}:/root/.aws" \
      -e AWS_PROFILE="$PROFILE" \
      -e AWS_DEFAULT_REGION="$REGION" \
      "$IMAGE" \
      aws sts get-caller-identity --output text --query 'UserId' > /dev/null 2>&1; then
    echo "❌ AWS credentials are missing or expired for profile: ${PROFILE}"
    echo "   Run okta-auth.sh to authenticate or refresh your session, then try again."
    exit 1
  fi

  # Run requested command
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*" docker run --rm -it \
    -v "${AWS_DIR_MOUNT}:/root/.aws" \
    -v "${WORK_DIR_MOUNT}:/work" \
    -w /work \
    -e AWS_PROFILE="$PROFILE" \
    -e AWS_DEFAULT_REGION="$REGION" \
    "$IMAGE" \
    "$@"

else
  mkdir -p "$HOME/.aws"

  # Credential check
  if ! docker run --rm \
      -v "$HOME/.aws:/root/.aws" \
      -e AWS_PROFILE="$PROFILE" \
      -e AWS_DEFAULT_REGION="$REGION" \
      "$IMAGE" \
      aws sts get-caller-identity --output text --query 'UserId' > /dev/null 2>&1; then
    echo "❌ AWS credentials are missing or expired for profile: ${PROFILE}"
    echo "   Run okta-auth.sh to authenticate or refresh your session, then try again."
    exit 1
  fi

  # Run requested command
  docker run --rm -it \
    -v "$HOME/.aws:/root/.aws" \
    -v "${MOUNT_DIR}:/work" \
    -w /work \
    -e AWS_PROFILE="$PROFILE" \
    -e AWS_DEFAULT_REGION="$REGION" \
    "$IMAGE" \
    "$@"
fi