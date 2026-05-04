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
#   ./tests/eth1/e2e_integration_test.sh [--cleanup] [--region REGION] [--prefix PREFIX] [--debug] [--from-phase N] [--only-phase N]
#
# Flags:
#   --cleanup        Destroy all deployed resources after the test run
#   --region         AWS region to deploy into (default: us-east-1)
#   --prefix         CDK stack name prefix (default: dev, or $CDK_PREFIX if set).
#                    The resulting stack name is "${PREFIX}NitroWalletEth".
#   --debug          Enable shell trace (set -x) and deploy the enclave in
#                    debug mode. In debug mode PCR0 is all zeros and is used
#                    in the KMS key policy instead of being fetched from the
#                    instance. See docs for implications of --debug-mode.
#   --from-phase N   Start from phase N (1..7). State from earlier phases is loaded
#                    from the state file if present. Default: 1
#   --only-phase N   Run only phase N. Implies --from-phase N and stops after it
#
# Phases:
#   1 = Environment validation
#   2 = Workspace setup (venv + deps)
#   3 = Build enclave binaries (kmstool_enclave_cli)
#   4 = CDK deploy
#   5 = Configure KMS key policy
#   6 = Generate Ethereum key & store via Lambda (set_key)
#   7 = Sign EIP-1559 transaction via Lambda (sign_transaction)

set -euo pipefail

###############################################################################
# Configuration
###############################################################################
PREFIX="${CDK_PREFIX:-dev}"
PREFIX_EXPLICIT=false
CLEANUP=false
REGION="us-east-1"
DEBUG=false
DEBUG_PCR0="000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
FROM_PHASE=1
ONLY_PHASE=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG_FILE="${SCRIPT_DIR}/e2e_test.log"
STATE_FILE="${SCRIPT_DIR}/e2e_state.env"
MAX_PCR0_RETRIES=10
PCR0_RETRY_INTERVAL=60

###############################################################################
# Parse arguments
###############################################################################
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cleanup)      CLEANUP=true; shift ;;
    --region)       REGION="$2"; shift 2 ;;
    --prefix)       PREFIX="$2"; PREFIX_EXPLICIT=true; shift 2 ;;
    --debug)        DEBUG=true; shift ;;
    --from-phase)   FROM_PHASE="$2"; shift 2 ;;
    --only-phase)   ONLY_PHASE="$2"; FROM_PHASE="$2"; shift 2 ;;
    *)              echo "Unknown option: $1"; exit 1 ;;
  esac
done

if ! [[ "$FROM_PHASE" =~ ^[1-7]$ ]]; then
  echo "Invalid --from-phase: $FROM_PHASE (must be 1..7)"; exit 1
fi
if [[ "$ONLY_PHASE" != "0" ]] && ! [[ "$ONLY_PHASE" =~ ^[1-7]$ ]]; then
  echo "Invalid --only-phase: $ONLY_PHASE (must be 1..7)"; exit 1
fi

# Enable shell trace when --debug is set (after arg parsing so flags themselves aren't traced).
if [[ "$DEBUG" == true ]]; then
  set -x
fi

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

# Returns 0 if phase N should run, 1 otherwise.
should_run() {
  local phase=$1
  [[ "$phase" -ge "$FROM_PHASE" ]] || return 1
  [[ "$ONLY_PHASE" == "0" || "$phase" == "$ONLY_PHASE" ]] || return 1
  return 0
}

# Persist a key=value pair into the state file.
save_state() {
  local key="$1" value="$2"
  if [[ -f "$STATE_FILE" ]]; then
    # remove any existing entry for this key
    grep -v "^${key}=" "$STATE_FILE" > "${STATE_FILE}.tmp" || true
    mv "${STATE_FILE}.tmp" "$STATE_FILE"
  fi
  # shellcheck disable=SC2129
  printf '%s=%q\n' "$key" "$value" >> "$STATE_FILE"
}

# Load all state variables from the state file (if present) into the current shell.
load_state() {
  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$STATE_FILE"
    log "Loaded state from $STATE_FILE"
  fi
}

# Verify a required variable is set (loaded from state or computed earlier).
require_var() {
  local name="$1"
  [[ -n "${!name:-}" ]] || fail "Required state variable '$name' is missing. Run earlier phases first or delete $STATE_FILE to start over."
}

cleanup_on_exit() {
  if [[ "$CLEANUP" == true ]]; then
    log "Cleanup flag set — destroying stack..."
    cd "$REPO_ROOT" 2>/dev/null || true
    cdk destroy "$STACK_NAME" --force 2>&1 | tee -a "$LOG_FILE" || warn "cdk destroy returned non-zero"
    rm -f "$STATE_FILE"
    log "Cleanup complete"
  fi
}
trap cleanup_on_exit EXIT

###############################################################################
# Load any previously-saved state (stack outputs, instance id, PCR0, etc.)
###############################################################################
# Remember CLI-provided prefix so state file can't override it
_CLI_PREFIX="$PREFIX"
load_state
# CLI flag wins over whatever was in the state file
if [[ "$PREFIX_EXPLICIT" == true ]]; then
  PREFIX="$_CLI_PREFIX"
fi
STACK_NAME="${PREFIX}NitroWalletEth"

log "=== Starting at phase $FROM_PHASE${ONLY_PHASE:+ (only phase $ONLY_PHASE)} ==="

###############################################################################
# Phase 1: Environment validation
###############################################################################
if should_run 1; then
  log "=== Phase 1: Environment Validation ==="

  for cmd in python3 pip3 jq aws docker node cdk openssl; do
    command -v "$cmd" >/dev/null 2>&1 || fail "Required command not found: $cmd"
  done
  log "All required CLI tools present"

  AWS_ACCOUNT=$(aws sts get-caller-identity --region "$REGION" | jq -r '.Account') \
    || fail "Unable to retrieve AWS caller identity — check credentials"
  log "AWS Account: $AWS_ACCOUNT (region: $REGION)"
  save_state AWS_ACCOUNT "$AWS_ACCOUNT"
  save_state REGION "$REGION"
  save_state PREFIX "$PREFIX"

  python3 -c "import venv" 2>/dev/null || fail "Python venv module not available"
  log "Python venv module available"
fi

###############################################################################
# Phase 2: Workspace Setup
###############################################################################
if should_run 2; then
  log "=== Phase 2: Workspace Setup ==="

  cd "$REPO_ROOT"

  [[ -f "app.py" && -f "cdk.json" ]] \
    || fail "Not in the expected repo root (missing app.py or cdk.json): $REPO_ROOT"
  log "Repository root: $REPO_ROOT"

  if [[ ! -d ".venv" ]]; then
    python3 -m venv .venv
    log "Created new Python venv"
  fi
  # shellcheck source=/dev/null
  source .venv/bin/activate
  log "Python venv activated"

  pip3 install -r requirements.txt 2>&1 | tail -5 | tee -a "$LOG_FILE"
  log "Python dependencies installed"
else
  # Later phases still need the repo root + venv activated.
  if [[ -d "$REPO_ROOT/.venv" ]]; then
    cd "$REPO_ROOT"
    # shellcheck source=/dev/null
    source .venv/bin/activate
  fi
fi

###############################################################################
# Phase 3: Build enclave binaries
###############################################################################
if should_run 3; then
  log "=== Phase 3: Build Enclave Binaries ==="

  ./scripts/build_kmstool_enclave_cli.sh 2>&1 | tee -a "$LOG_FILE"

  [[ -d "$REPO_ROOT/application/eth1/enclave/kms" ]] \
    || fail "Enclave artifacts directory not found after build"
  log "kmstool-enclave-cli build successful"
fi

###############################################################################
# Phase 4: CDK Deploy
###############################################################################
if should_run 4; then
  log "=== Phase 4: CDK Deploy ==="

  require_var AWS_ACCOUNT
  require_var REGION

  export CDK_DEPLOY_REGION="$REGION"
  export CDK_DEPLOY_ACCOUNT="$AWS_ACCOUNT"
  export CDK_PREFIX="$PREFIX"

  # Podman doesn't support `docker buildx --load`; bypass any CDK docker wrapper
  if docker version 2>&1 | grep -qi podman; then
    export CDK_DOCKER=podman
  fi

  cd "$REPO_ROOT"
  cdk bootstrap 2>&1 | tee -a "$LOG_FILE"
  log "CDK bootstrap complete"

  CDK_DEPLOY_ARGS=("$STACK_NAME" "--require-approval" "never")
  if [[ "$DEBUG" == true ]]; then
    # Pass deployment=dev which causes the stack to inject --debug-mode into
    # the enclave start command. When the enclave runs in debug mode its
    # PCR0 is all zeros, which phase 5 uses verbatim for the KMS policy.
    CDK_DEPLOY_ARGS+=("-c" "deployment=dev")
    log "Deploying in debug mode (enclave will be started with --debug-mode)"
  else
    # Force deployment=prod so the enclave starts without --debug-mode and
    # phase 5 fetches a real PCR0 from the running instance.
    CDK_DEPLOY_ARGS+=("-c" "deployment=prod")
    log "Deploying in production mode (enclave without --debug-mode)"
  fi
  cdk deploy "${CDK_DEPLOY_ARGS[@]}" 2>&1 | tee -a "$LOG_FILE"
  log "CDK deploy complete"

  # Refresh stack outputs in state — deploy may have changed ARNs/IDs or
  # replaced the Lambda function. Also clears local variables so that the
  # post-phase-4 refresh block below unconditionally re-fetches them.
  unset ASG_GROUP EC2_ROLE_ARN KMS_KEY_ID LAMBDA_ROLE_ARN LAMBDA_FN

  log "Refreshing stack outputs in state file..."
  ASG_GROUP=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='ASGGroupName'].OutputValue" \
    --output text) || fail "Could not retrieve ASGGroupName"
  EC2_ROLE_ARN=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='EC2InstanceRoleARN'].OutputValue" \
    --output text) || fail "Could not retrieve EC2InstanceRoleARN"
  KMS_KEY_ID=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='KMSKeyID'].OutputValue" \
    --output text) || fail "Could not retrieve KMSKeyID"
  LAMBDA_ROLE_ARN=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='LambdaExecutionRoleARN'].OutputValue" \
    --output text) || fail "Could not retrieve LambdaExecutionRoleARN"
  LAMBDA_FN=$(aws lambda list-functions --region "$REGION" \
    --query "Functions[?starts_with(FunctionName, '${STACK_NAME}-NitroInvokeLambda')].FunctionName" \
    --output text) || fail "Could not find NitroInvoke Lambda function"

  save_state ASG_GROUP "$ASG_GROUP"
  save_state EC2_ROLE_ARN "$EC2_ROLE_ARN"
  save_state KMS_KEY_ID "$KMS_KEY_ID"
  save_state LAMBDA_ROLE_ARN "$LAMBDA_ROLE_ARN"
  save_state LAMBDA_FN "$LAMBDA_FN"
  log "State refreshed after deploy"
fi

# Always refresh stack outputs if any downstream phase (5+) will run.
# This makes phases 5/6/7 independently runnable without needing the raw deploy output.
if should_run 5 || should_run 6 || should_run 7; then
  require_var REGION

  if [[ -z "${ASG_GROUP:-}" ]] || [[ -z "${EC2_ROLE_ARN:-}" ]] || [[ -z "${KMS_KEY_ID:-}" ]] || [[ -z "${LAMBDA_ROLE_ARN:-}" ]]; then
    log "Fetching stack outputs from CloudFormation..."

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

    save_state ASG_GROUP "$ASG_GROUP"
    save_state EC2_ROLE_ARN "$EC2_ROLE_ARN"
    save_state KMS_KEY_ID "$KMS_KEY_ID"
    save_state LAMBDA_ROLE_ARN "$LAMBDA_ROLE_ARN"
  fi

  log "Stack outputs:"
  log "  ASG Group:    $ASG_GROUP"
  log "  EC2 Role:     $EC2_ROLE_ARN"
  log "  KMS Key ID:   $KMS_KEY_ID"
  log "  Lambda Role:  $LAMBDA_ROLE_ARN"
fi

###############################################################################
# Phase 5: Configure KMS key policy
###############################################################################
if should_run 5; then
  log "=== Phase 5: Configure KMS Key Policy ==="

  require_var AWS_ACCOUNT
  require_var ASG_GROUP
  require_var EC2_ROLE_ARN
  require_var KMS_KEY_ID
  require_var LAMBDA_ROLE_ARN

  INSTANCE_ID=$("$REPO_ROOT/scripts/get_asg_instances.sh" "$ASG_GROUP" | grep -oE 'i-[0-9a-f]+' | head -1) \
    || fail "Could not retrieve instance ID from ASG"
  log "EC2 Instance: $INSTANCE_ID"
  save_state INSTANCE_ID "$INSTANCE_ID"

  if [[ "$DEBUG" == true ]]; then
    PCR0="$DEBUG_PCR0"
    log "Debug mode: using all-zeros PCR0 (skipping instance fetch)"
  else
    PCR0=""
    for i in $(seq 1 $MAX_PCR0_RETRIES); do
      PCR0=$("$REPO_ROOT/scripts/get_pcr0.sh" "$INSTANCE_ID" 2>/dev/null | tr -d '[:space:]') || true
      if [[ -n "$PCR0" ]]; then
        break
      fi
      warn "PCR0 empty on attempt $i/$MAX_PCR0_RETRIES — retrying in ${PCR0_RETRY_INTERVAL}s"
      sleep "$PCR0_RETRY_INTERVAL"
    done
    [[ -n "$PCR0" ]] || fail "Could not retrieve PCR0 after $MAX_PCR0_RETRIES attempts"
  fi
  log "PCR0: $PCR0"
  save_state PCR0 "$PCR0"

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
fi

# Resolve the Lambda function name once for phases 6 and 7.
if should_run 6 || should_run 7; then
  if [[ -z "${LAMBDA_FN:-}" ]]; then
    LAMBDA_FN=$(aws lambda list-functions \
      --region "$REGION" \
      --query "Functions[?starts_with(FunctionName, '${STACK_NAME}-NitroInvokeLambda')].FunctionName" \
      --output text) || fail "Could not find NitroInvoke Lambda function"
    save_state LAMBDA_FN "$LAMBDA_FN"
  fi
  log "Lambda function: $LAMBDA_FN"
fi

###############################################################################
# Phase 6: Generate Ethereum key & store via Lambda
###############################################################################
if should_run 6; then
  log "=== Phase 6: Generate Ethereum Key & Store ==="

  require_var REGION
  require_var LAMBDA_FN

  openssl ecparam -name secp256k1 -genkey -noout | openssl ec -text -noout > "${SCRIPT_DIR}/eth_key_raw" 2>/dev/null
  ETH_KEY=$(grep priv -A 3 "${SCRIPT_DIR}/eth_key_raw" | tail -n +2 | tr -d '\n[:space:]:' | sed 's/^00//')
  [[ ${#ETH_KEY} -eq 64 ]] || fail "Generated Ethereum key is not 64 hex chars (got ${#ETH_KEY})"
  log "Ethereum test key generated (${#ETH_KEY} chars)"
  save_state ETH_KEY "$ETH_KEY"

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
fi

###############################################################################
# Phase 7: Sign Ethereum EIP-1559 transaction
###############################################################################
if should_run 7; then
  log "=== Phase 7: Sign Ethereum Transaction ==="

  require_var REGION
  require_var LAMBDA_FN

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

  # Always log the full response body for visibility; also dump metadata on failure.
  log "Lambda response body:"
  cat "${SCRIPT_DIR}/sign_tx_response.json" | tee -a "$LOG_FILE"
  echo "" | tee -a "$LOG_FILE"

  SIGNED_TX=$(jq -r '.transaction_signed // .signed_transaction // .body // empty' "${SCRIPT_DIR}/sign_tx_response.json")
  if [[ -z "$SIGNED_TX" ]]; then
    warn "No signed transaction in Lambda response. Full invoke metadata:"
    echo "$SIGN_RESPONSE" | tee -a "$LOG_FILE"
    fail "No signed transaction in Lambda response (see body and metadata above)"
  fi
  log "sign_transaction successful"
  log "Signed TX (truncated): ${SIGNED_TX:0:80}..."
fi

###############################################################################
# Summary
###############################################################################
echo ""
log "========================================="
log "  E2E Integration Test PASSED"
log "========================================="
log "  Region:     ${REGION:-}"
log "  Account:    ${AWS_ACCOUNT:-}"
log "  Stack:      $STACK_NAME"
log "  Prefix:     $PREFIX"
log "  Lambda:     ${LAMBDA_FN:-}"
log "  Cleanup:    $CLEANUP"
log "  Debug:      $DEBUG"
log "  Log:        $LOG_FILE"
log "  State:      $STATE_FILE"
log "========================================="
