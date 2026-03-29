#!/bin/bash
# awstunnel.sh — start an SSM tunnel to a remote target
#
# Usage:
#   awstunnel.sh jupyter      <instance-id> [remote-port] [local-port]
#   awstunnel.sh db           <instance-id> <remote-host> <remote-port> [local-port]
#   awstunnel.sh port-forward <instance-id> <remote-host> <remote-port> [local-port]
#
# Examples:
#   awstunnel.sh jupyter  $JUPYTER_INSTANCE
#   awstunnel.sh jupyter  i-0abc1234567890def
#   awstunnel.sh db       $PROD_DB_INSTANCE $PROD_DB_HOST $PROD_DB_PORT
#   awstunnel.sh db       i-0abc1234567890def mydb.cluster.us-west-2.rds.amazonaws.com 5432
#   awstunnel.sh db       i-0abc1234567890def localhost 3306
#   awstunnel.sh port-forward i-0abc1234567890def internal-service.local 80 8080

set -euo pipefail

IMAGE="aws-okta-toolbox"
PROFILE="${AWS_PROFILE:-default}"
REGION="${AWS_DEFAULT_REGION:-us-west-2}"

# ── Platform-specific Docker wrapper ──────────────────────────────────────────
if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* || "$OSTYPE" == win32* ]]; then
  if [[ -z "${USERPROFILE:-}" ]]; then
    echo "❌ USERPROFILE is not set. Cannot determine Windows home directory."
    exit 1
  fi

  AWS_DIR_CREATE="$(cygpath -u "$USERPROFILE")/.aws"
  AWS_DIR_MOUNT="$(cygpath -w "$USERPROFILE")\\.aws"

  mkdir -p "$AWS_DIR_CREATE"

  docker_aws() {
    MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*" docker "$@"
  }
else
  AWS_DIR_CREATE="$HOME/.aws"
  AWS_DIR_MOUNT="$AWS_DIR_CREATE"

  mkdir -p "$AWS_DIR_CREATE"

  docker_aws() {
    docker "$@"
  }
fi

# ── Credential check ──────────────────────────────────────────────────────────
check_credentials() {
  docker_aws run --rm \
    -v "${AWS_DIR_MOUNT}:/root/.aws" \
    -e AWS_PROFILE="$PROFILE" \
    -e AWS_DEFAULT_REGION="$REGION" \
    "$IMAGE" \
    aws sts get-caller-identity --output text --query 'UserId' > /dev/null 2>&1
}

if ! check_credentials; then
  echo "❌ AWS credentials are missing or expired for profile: ${PROFILE}"
  echo "   Run okta-auth.sh to re-authenticate, then try again."
  exit 1
fi

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
  grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,1\}//'
  exit 1
}

[[ $# -lt 1 ]] && usage

TUNNEL_TYPE="$1"

# ── Instance ID validation helper ─────────────────────────────────────────────
require_instance_id() {
  local provided="${1:-}"
  local envvar="${2:-}"
  local envval="${3:-}"

  if [[ -z "$provided" ]]; then
    echo "❌ Missing instance ID for tunnel type: ${TUNNEL_TYPE}"
    if [[ -n "$envvar" && -n "$envval" ]]; then
      echo "   ${envvar} is set to: ${envval}"
      echo "   Usage: awstunnel.sh ${TUNNEL_TYPE} \$${envvar}"
    elif [[ -n "$envvar" ]]; then
      echo "   Tip: set ${envvar} in your env file, then run:"
      echo "   awstunnel.sh ${TUNNEL_TYPE} \$${envvar}"
    else
      echo "   Usage: awstunnel.sh ${TUNNEL_TYPE} <instance-id>"
    fi
    exit 1
  fi
}

case "$TUNNEL_TYPE" in

  # ── Jupyter ────────────────────────────────────────────────────────────────
  jupyter)
    INSTANCE_ID="${2:-}"
    require_instance_id "$INSTANCE_ID" "JUPYTER_INSTANCE" "${JUPYTER_INSTANCE:-}"
    REMOTE_PORT="${3:-8888}"
    LOCAL_PORT="${4:-$REMOTE_PORT}"
    echo "🔬 Jupyter tunnel"
    echo "   Instance : $INSTANCE_ID"
    echo "   Tunnel   : localhost:$REMOTE_PORT on instance → localhost:$LOCAL_PORT on your machine"
    echo ""
    echo "   Once connected, open: http://localhost:${LOCAL_PORT}"
    echo "   Press Ctrl-C to close the tunnel."
    echo ""
    docker_aws run --rm -it \
      --name "ssm-jupyter-${LOCAL_PORT}" \
      -p "${LOCAL_PORT}:${LOCAL_PORT}" \
      -v "${AWS_DIR_MOUNT}:/root/.aws" \
      -e AWS_PROFILE="$PROFILE" \
      -e AWS_DEFAULT_REGION="$REGION" \
      "$IMAGE" \
      aws ssm start-session \
        --region "$REGION" \
        --profile "$PROFILE" \
        --target "$INSTANCE_ID" \
        --document-name AWS-StartPortForwardingSessionToRemoteHost \
        --parameters "host=localhost,portNumber=${REMOTE_PORT},localPortNumber=${LOCAL_PORT}"
    ;;

  # ── Database ───────────────────────────────────────────────────────────────
  db)
    INSTANCE_ID="${2:-}"
    require_instance_id "$INSTANCE_ID" "PROD_DB_INSTANCE" "${PROD_DB_INSTANCE:-}"
    if [[ $# -lt 4 ]]; then
      echo "❌ Missing arguments for db tunnel."
      echo "   Usage: awstunnel.sh db <instance-id> <remote-host> <remote-port> [local-port]"
      echo ""
      echo "   RDS example (bastion → RDS endpoint):"
      echo "   awstunnel.sh db \$PROD_DB_INSTANCE \$PROD_DB_HOST \$PROD_DB_PORT"
      echo ""
      echo "   EC2-hosted DB example (DB running on the instance itself):"
      echo "   awstunnel.sh db i-0abc1234567890def localhost 5432"
      exit 1
    fi
    REMOTE_HOST="$3"
    REMOTE_PORT="$4"
    LOCAL_PORT="${5:-$REMOTE_PORT}"
    echo "🗄️  Database tunnel"
    echo "   Instance    : $INSTANCE_ID"
    echo "   Remote      : $REMOTE_HOST:$REMOTE_PORT → localhost:$LOCAL_PORT on your machine"
    echo "   Connect your DB client to: localhost:${LOCAL_PORT}"
    echo "   Press Ctrl-C to close the tunnel."
    echo ""
    docker_aws run --rm -it \
      --name "ssm-db-${LOCAL_PORT}" \
      -p "${LOCAL_PORT}:${LOCAL_PORT}" \
      -v "${AWS_DIR_MOUNT}:/root/.aws" \
      -e AWS_PROFILE="$PROFILE" \
      -e AWS_DEFAULT_REGION="$REGION" \
      "$IMAGE" \
      aws ssm start-session \
        --region "$REGION" \
        --profile "$PROFILE" \
        --target "$INSTANCE_ID" \
        --document-name AWS-StartPortForwardingSessionToRemoteHost \
        --parameters "host=${REMOTE_HOST},portNumber=${REMOTE_PORT},localPortNumber=${LOCAL_PORT}"
    ;;

  # ── Generic port forward ───────────────────────────────────────────────────
  port-forward)
    INSTANCE_ID="${2:-}"
    require_instance_id "$INSTANCE_ID" "" ""
    if [[ $# -lt 4 ]]; then
      echo "❌ Missing arguments for port-forward."
      echo "   Usage: awstunnel.sh port-forward <instance-id> <remote-host> <remote-port> [local-port]"
      exit 1
    fi
    REMOTE_HOST="$3"
    REMOTE_PORT="$4"
    LOCAL_PORT="${5:-$REMOTE_PORT}"
    echo "🔗 Port-forward tunnel"
    echo "   Instance    : $INSTANCE_ID"
    echo "   Remote      : $REMOTE_HOST:$REMOTE_PORT → localhost:$LOCAL_PORT on your machine"
    echo "   Press Ctrl-C to close the tunnel."
    echo ""
    docker_aws run --rm -it \
      --name "ssm-portfwd-${LOCAL_PORT}" \
      -p "${LOCAL_PORT}:${LOCAL_PORT}" \
      -v "${AWS_DIR_MOUNT}:/root/.aws" \
      -e AWS_PROFILE="$PROFILE" \
      -e AWS_DEFAULT_REGION="$REGION" \
      "$IMAGE" \
      aws ssm start-session \
        --region "$REGION" \
        --profile "$PROFILE" \
        --target "$INSTANCE_ID" \
        --document-name AWS-StartPortForwardingSessionToRemoteHost \
        --parameters "host=${REMOTE_HOST},portNumber=${REMOTE_PORT},localPortNumber=${LOCAL_PORT}"
    ;;

  *)
    echo "❌ Unknown tunnel type: $TUNNEL_TYPE"
    echo "   Valid types: jupyter, db, port-forward"
    usage
    ;;
esac