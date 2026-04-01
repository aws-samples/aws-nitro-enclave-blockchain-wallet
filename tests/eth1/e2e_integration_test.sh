#!/usr/bin/env bash
#
# E2E Integration Test for AWS Nitro Enclaves Blockchain Wallet Workshop
#
# Validates environment, builds enclave binaries, deploys via CDK,
# configures KMS key policy, generates an Ethereum key, encrypts/stores it,
# and signs an EIP-1559 transaction.
#
# Must be run from within the cloned repository.
#
# Usage:
#   ./tests/eth1/e2e_integration_test.sh [--cleanup] [--region REGION]
#
# Flags:
#   --cleanup   Destroy all deployed resources after the test run
#   --region    AWS region to deploy into (default: us-east-1)

set -euo pipefail

###############################################################################
# Configuration
###############################################################################
STACK_NAME="devNitroWalletEth"
CLEANUP=false
REGION="us-east-1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG_FILE="${SCRIPT_DIR}/e2e_test.log"
MAX_PCR0_RETRIES=10
PCR0_RETRY_INTERVAL=60

###############################################################################
# Parse arguments
###############################################################################
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cleanup) CLEANUP=true; shift ;;
    --region)  REGION="$2"; shift 2 ;;
    *)         echo "Unknown option: $1"; exit 1 ;;
  esac
done

###############################################################################
# Helpers
###############################################################################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✓ $*${NC}" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠ $*${NC}" | tee -a "$LOG_FILE"; }
fail() { echo -e "${RED}[$(date '+%H:%M:%S')] ✗ $*${NC}" | tee -a "$LOG_FILE"; exit 1; }

cleanup_on_exit() {
  if [[ "$CLEANUP" == true ]]; then
    log "Cleanup flag set — destroying stack..."
    cd "$REPO_ROOT" 2>/dev/null || true
    cdk destroy "$STACK_NAME" --force 2>&1 | tee -a "$LOG_FILE" || warn "cdk destroy returned non-zero"
    log "Cleanup complete"
  fi
}
trap cleanup_on_exit EXIT

###############################################################################
# Phase 1: Environment validation
###############################################################################
log "=== Phase 1: Environment Validation ==="

# Check required CLI tools
for cmd in python3 pip3 jq aws docker node cdk openssl; do
  command -v "$cmd" >/dev/null 2>&1 || fail "Required command not found: $cmd"
done
log "All required CLI tools present"

# Validate AWS credentials
AWS_ACCOUNT=$(aws sts get-caller-identity --region "$REGION" | jq -r '.Account') \
  || fail "Unable to retrieve AWS caller identity — check credentials"
log "AWS Account: $AWS_ACCOUNT (region: $REGION)"

# Validate Python venv support
python3 -c "import venv" 2>/dev/null || fail "Python venv module not available"
log "Python venv module available"

###############################################################################
# Phase 2: Workspace Setup
###############################################################################
log "=== Phase 2: Workspace Setup ==="

cd "$REPO_ROOT"

# Verify we're in the correct repo
[[ -f "app.py" && -f "cdk.json" ]] \
  || fail "Not in the expected repo root (missing app.py or cdk.json): $REPO_ROOT"
log "Repository root: $REPO_ROOT"

# Create and activate virtual environment
if [[ ! -d ".venv" ]]; then
  python3 -m venv .venv
  log "Created new Python venv"
fi
# shellcheck source=/dev/null
source .venv/bin/activate
log "Python venv activated"

# Install dependencies
pip3 install -r requirements.txt 2>&1 | tail -5 | tee -a "$LOG_FILE"
log "Python dependencies installed"

###############################################################################
# Phase 3: Build enclave binaries
###############################################################################
log "=== Phase 3: Build Enclave Binaries ==="

./scripts/build_kmstool_enclave_cli.sh 2>&1 | tee -a "$LOG_FILE"

[[ -d "application/eth1/enclave/kms" ]] \
  || fail "Enclave artifacts directory not found after build"
log "kmstool-enclave-cli build successful"

###############################################################################
# Phase 4: CDK Deploy
###############################################################################
log "=== Phase 4: CDK Deploy ==="

export CDK_DEPLOY_REGION="$REGION"
export CDK_DEPLOY_ACCOUNT="$AWS_ACCOUNT"

# Podman doesn't support `docker buildx --load`; bypass any CDK docker wrapper
if docker version 2>&1 | grep -qi podman; then
  export CDK_DOCKER=podman
fi

cdk bootstrap 2>&1 | tee -a "$LOG_FILE"
log "CDK bootstrap complete"

cdk deploy "$STACK_NAME" --require-approval never 2>&1 | tee -a "$LOG_FILE"
log "CDK deploy complete"

# Extract stack outputs
ASG_GROUP=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='ASGGroupName'].OutputValue" \
  --output text) || fail "Could not retrieve ASGGroupName"

EC2_ROLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='EC2InstanceRoleARN'].OutputValue" \
  --output text) || fail "Could not retrieve EC2InstanceRoleARN"

KMS_KEY_ID=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='KMSKeyID'].OutputValue" \
  --output text) || fail "Could not retrieve KMSKeyID"

LAMBDA_ROLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='LambdaExecutionRoleARN'].OutputValue" \
  --output text) || fail "Could not retrieve LambdaExecutionRoleARN"

log "Stack outputs:"
log "  ASG Group:    $ASG_GROUP"
log "  EC2 Role:     $EC2_ROLE_ARN"
log "  KMS Key ID:   $KMS_KEY_ID"
log "  Lambda Role:  $LAMBDA_ROLE_ARN"

###############################################################################
# Phase 5: Configure KMS key policy
###############################################################################
log "=== Phase 5: Configure KMS Key Policy ==="

# Get EC2 instance ID from ASG
INSTANCE_ID=$(./scripts/get_asg_instances.sh "$ASG_GROUP" | grep -oE 'i-[0-9a-f]+' | head -1) \
  || fail "Could not retrieve instance ID from ASG"
log "EC2 Instance: $INSTANCE_ID"

# Fetch PCR0 with retries (enclave may still be initializing)
PCR0=""
for i in $(seq 1 $MAX_PCR0_RETRIES); do
  PCR0=$(./scripts/get_pcr0.sh "$INSTANCE_ID" 2>/dev/null | tr -d '[:space:]') || true
  if [[ -n "$PCR0" ]]; then
    break
  fi
  warn "PCR0 empty on attempt $i/$MAX_PCR0_RETRIES — retrying in ${PCR0_RETRY_INTERVAL}s"
  sleep "$PCR0_RETRY_INTERVAL"
done
[[ -n "$PCR0" ]] || fail "Could not retrieve PCR0 after $MAX_PCR0_RETRIES attempts"
log "PCR0: $PCR0"

# Build and apply KMS key policy
KMS_ADMIN_ARN="arn:aws:iam::${AWS_ACCOUNT}:root"

KMS_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Enable decrypt from enclave",
      "Effect": "Allow",
      "Principal": { "AWS": "${EC2_ROLE_ARN}" },
      "Action": "kms:Decrypt",
      "Resource": "*",
      "Condition": {
        "StringEqualsIgnoreCase": {
          "kms:RecipientAttestation:ImageSha384": "${PCR0}"
        }
      }
    },
    {
      "Sid": "Enable encrypt from lambda",
      "Effect": "Allow",
      "Principal": { "AWS": "${LAMBDA_ROLE_ARN}" },
      "Action": "kms:Encrypt",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Principal": { "AWS": "${KMS_ADMIN_ARN}" },
      "Action": [
        "kms:Create*", "kms:Describe*", "kms:Enable*", "kms:List*",
        "kms:Put*", "kms:Update*", "kms:Revoke*", "kms:Disable*",
        "kms:Get*", "kms:Delete*", "kms:ScheduleKeyDeletion",
        "kms:CancelKeyDeletion", "kms:GenerateDataKey",
        "kms:TagResource", "kms:UntagResource"
      ],
      "Resource": "*"
    }
  ]
}
EOF
)

aws kms put-key-policy \
  --key-id "$KMS_KEY_ID" \
  --policy-name default \
  --policy "$KMS_POLICY" \
  --region "$REGION" 2>&1 | tee -a "$LOG_FILE"
log "KMS key policy applied"

###############################################################################
# Phase 6: Generate Ethereum key & store via Lambda
###############################################################################
log "=== Phase 6: Generate Ethereum Key & Store ==="

# Generate a test Ethereum private key
openssl ecparam -name secp256k1 -genkey -noout | openssl ec -text -noout > "${SCRIPT_DIR}/eth_key_raw" 2>/dev/null
ETH_KEY=$(cat "${SCRIPT_DIR}/eth_key_raw" | grep priv -A 3 | tail -n +2 | tr -d '\n[:space:]:' | sed 's/^00//')
[[ ${#ETH_KEY} -eq 64 ]] || fail "Generated Ethereum key is not 64 hex chars (got ${#ETH_KEY})"
log "Ethereum test key generated (${#ETH_KEY} chars)"

# Find the Lambda function name
LAMBDA_FN=$(aws lambda list-functions \
  --region "$REGION" \
  --query "Functions[?starts_with(FunctionName, '${STACK_NAME}-NitroInvokeLambda')].FunctionName" \
  --output text) || fail "Could not find NitroInvoke Lambda function"
log "Lambda function: $LAMBDA_FN"

# Invoke set_key operation
SET_KEY_PAYLOAD=$(jq -n --arg key "$ETH_KEY" '{"operation":"set_key","eth_key":$key}')
SET_KEY_RESPONSE=$(aws lambda invoke \
  --function-name "$LAMBDA_FN" \
  --payload "$SET_KEY_PAYLOAD" \
  --cli-binary-format raw-in-base64-out \
  --region "$REGION" \
  "${SCRIPT_DIR}/set_key_response.json" 2>&1) || fail "Lambda set_key invocation failed"

SET_KEY_STATUS=$(echo "$SET_KEY_RESPONSE" | jq -r '.StatusCode // empty')
[[ "$SET_KEY_STATUS" == "200" ]] || fail "set_key returned status $SET_KEY_STATUS"
log "set_key operation successful"

###############################################################################
# Phase 7: Sign Ethereum EIP-1559 transaction
###############################################################################
log "=== Phase 7: Sign Ethereum Transaction ==="

SIGN_PAYLOAD=$(cat <<'SIGN_EOF'
{
  "operation": "sign_transaction",
  "transaction_payload": {
    "value": 0.01,
    "to": "0xa5D3241A1591061F2a4bB69CA0215F66520E67cf",
    "nonce": 0,
    "type": 2,
    "chainId": 4,
    "gas": 100000,
    "maxFeePerGas": 100000000000,
    "maxPriorityFeePerGas": 3000000000
  }
}
SIGN_EOF
)

SIGN_RESPONSE=$(aws lambda invoke \
  --function-name "$LAMBDA_FN" \
  --payload "$SIGN_PAYLOAD" \
  --cli-binary-format raw-in-base64-out \
  --region "$REGION" \
  "${SCRIPT_DIR}/sign_tx_response.json" 2>&1) || fail "Lambda sign_transaction invocation failed"

SIGN_STATUS=$(echo "$SIGN_RESPONSE" | jq -r '.StatusCode // empty')
[[ "$SIGN_STATUS" == "200" ]] || fail "sign_transaction returned status $SIGN_STATUS"

# Validate the signed transaction is present in the response
SIGNED_TX=$(jq -r '.transaction_signed // .signed_transaction // .body // empty' "${SCRIPT_DIR}/sign_tx_response.json")
[[ -n "$SIGNED_TX" ]] || fail "No signed transaction in Lambda response"
log "sign_transaction successful"
log "Signed TX (truncated): ${SIGNED_TX:0:80}..."

###############################################################################
# Summary
###############################################################################
echo ""
log "========================================="
log "  E2E Integration Test PASSED"
log "========================================="
log "  Region:     $REGION"
log "  Account:    $AWS_ACCOUNT"
log "  Stack:      $STACK_NAME"
log "  Lambda:     $LAMBDA_FN"
log "  Cleanup:    $CLEANUP"
log "  Log:        $LOG_FILE"
log "========================================="
