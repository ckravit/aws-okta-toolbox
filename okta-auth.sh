#!/bin/bash
# okta-auth.sh
# Run this whenever your AWS session expires.
# Prints a URL + code — open the URL in your browser, approve in Okta,
# then return here to select your account and role.
# Credentials are written to your host AWS credentials file and exit. No lingering container.
#
# Usage:
#   ./okta-auth.sh                        # uses AWS_PROFILE or "default"
#   ./okta-auth.sh --profile my-profile   # specific named profile
#   AWS_DEFAULT_REGION=us-west-2 ./okta-auth.sh
#
# Configuration (edit these or set as environment variables):
OKTA_ORG_DOMAIN="${OKTA_ORG_DOMAIN:-}"         # e.g. mycompany.okta.com
OKTA_OIDC_CLIENT_ID="${OKTA_OIDC_CLIENT_ID:-}" # from your Okta admin

set -euo pipefail

PROFILE="${AWS_PROFILE:-default}"
REGION="${AWS_DEFAULT_REGION:-us-west-2}"
IMAGE="aws-okta-toolbox"

# Parse optional --profile flag
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile|-p)
      PROFILE="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

# Validate required config
if [[ -z "$OKTA_ORG_DOMAIN" || -z "$OKTA_OIDC_CLIENT_ID" ]]; then
  echo "❌ Missing Okta configuration."
  echo "   Set OKTA_ORG_DOMAIN and OKTA_OIDC_CLIENT_ID in this script or as env vars."
  echo "   Example:"
  echo "     export OKTA_ORG_DOMAIN=mycompany.okta.com"
  echo "     export OKTA_OIDC_CLIENT_ID=0oa1b2c3d4e5f6g7h8i9"
  exit 1
fi

echo "🔐 Okta authentication — profile: ${PROFILE}"
echo ""
echo "   A URL will appear below. Open it in your browser and approve the Okta request."
echo "   Then come back here to select your AWS account and role."
echo ""

# Detect Windows Git Bash / MSYS / Cygwin
if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* || "$OSTYPE" == win32* ]]; then
  if [[ -z "${USERPROFILE:-}" ]]; then
    echo "❌ USERPROFILE is not set. Cannot determine Windows home directory."
    exit 1
  fi

  # Path for mkdir/cat/etc. inside Git Bash
  AWS_DIR_CREATE="$(cygpath -u "$USERPROFILE")/.aws"
  # Path for docker.exe bind mount
  AWS_DIR_MOUNT="$(cygpath -w "$USERPROFILE")\\.aws"

  mkdir -p "$AWS_DIR_CREATE"

  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*" docker run --rm -it \
    -v "${AWS_DIR_MOUNT}:/root/.aws" \
    -e AWS_DEFAULT_REGION="$REGION" \
    "$IMAGE" \
    okta-aws-cli \
      --org-domain "$OKTA_ORG_DOMAIN" \
      --oidc-client-id "$OKTA_OIDC_CLIENT_ID" \
      --write-aws-credentials \
      --aws-credentials /root/.aws/credentials \
      --profile "$PROFILE"

  CREDENTIALS_FILE="${AWS_DIR_CREATE}/credentials"
else
  AWS_DIR_CREATE="$HOME/.aws"
  mkdir -p "$AWS_DIR_CREATE"

  docker run --rm -it \
    -v "${AWS_DIR_CREATE}:/root/.aws" \
    -e AWS_DEFAULT_REGION="$REGION" \
    "$IMAGE" \
    okta-aws-cli \
      --org-domain "$OKTA_ORG_DOMAIN" \
      --oidc-client-id "$OKTA_OIDC_CLIENT_ID" \
      --write-aws-credentials \
      --aws-credentials /root/.aws/credentials \
      --profile "$PROFILE"

  CREDENTIALS_FILE="${AWS_DIR_CREATE}/credentials"
fi

echo ""
echo "✅ Done. Credentials written to ${CREDENTIALS_FILE} (profile: ${PROFILE})"
echo "   They are now available to all tunnel and SSH commands on this machine."