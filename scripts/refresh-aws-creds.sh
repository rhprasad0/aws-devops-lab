#!/usr/bin/env bash
# =============================================================================
# refresh-aws-creds.sh
# =============================================================================
# Refreshes AWS credentials for the MCP server by extracting temporary
# credentials from the AWS CLI v2 browser-based login cache.
#
# WHY THIS IS NEEDED:
# - AWS CLI v2's `aws login` command stores credentials in a special cache
#   format (~/.aws/login/cache/) that MCP servers can't read directly
# - MCP servers (like the Terraform MCP server) need credentials in the
#   standard ~/.aws/credentials file format
# - This script bridges that gap by extracting and converting the credentials
#
# USAGE:
#   ./scripts/refresh-aws-creds.sh
#
# PREREQUISITES:
#   - jq must be installed
#   - You must have run `aws login` first
#
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔄 Refreshing AWS credentials for MCP server..."

# Check for jq
if ! command -v jq &> /dev/null; then
    echo -e "${RED}❌ Error: jq is required but not installed.${NC}"
    echo "   Install with: sudo apt-get install jq"
    exit 1
fi

# Find the cache file
CACHE_DIR="$HOME/.aws/login/cache"
if [ ! -d "$CACHE_DIR" ]; then
    echo -e "${RED}❌ Error: AWS login cache directory not found.${NC}"
    echo "   Run 'aws login' first to authenticate."
    exit 1
fi

CACHE_FILE=$(ls "$CACHE_DIR"/*.json 2>/dev/null | head -1)
if [ -z "$CACHE_FILE" ] || [ ! -f "$CACHE_FILE" ]; then
    echo -e "${RED}❌ Error: No cached credentials found.${NC}"
    echo "   Run 'aws login' first to authenticate."
    exit 1
fi

# Check if credentials have expired
EXPIRES_AT=$(jq -r '.accessToken.expiresAt // empty' "$CACHE_FILE")
if [ -n "$EXPIRES_AT" ]; then
    EXPIRES_EPOCH=$(date -d "$EXPIRES_AT" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$EXPIRES_AT" +%s 2>/dev/null || echo "0")
    NOW_EPOCH=$(date +%s)
    
    if [ "$EXPIRES_EPOCH" -lt "$NOW_EPOCH" ]; then
        echo -e "${RED}❌ Error: Cached credentials have expired.${NC}"
        echo "   Expired at: $EXPIRES_AT"
        echo "   Run 'aws login' to refresh your session."
        exit 1
    fi
    
    # Calculate remaining time
    REMAINING=$((EXPIRES_EPOCH - NOW_EPOCH))
    REMAINING_MINS=$((REMAINING / 60))
    
    if [ "$REMAINING_MINS" -lt 5 ]; then
        echo -e "${YELLOW}⚠️  Warning: Credentials expire in $REMAINING_MINS minutes.${NC}"
        echo "   Consider running 'aws login' to refresh."
    fi
fi

# Extract credentials
ACCESS_KEY=$(jq -r '.accessToken.accessKeyId // empty' "$CACHE_FILE")
SECRET_KEY=$(jq -r '.accessToken.secretAccessKey // empty' "$CACHE_FILE")
SESSION_TOKEN=$(jq -r '.accessToken.sessionToken // empty' "$CACHE_FILE")

if [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ]; then
    echo -e "${RED}❌ Error: Could not extract credentials from cache.${NC}"
    echo "   The cache file may be corrupted. Run 'aws login' again."
    exit 1
fi

# Write credentials file
CREDENTIALS_FILE="$HOME/.aws/credentials"
cat > "$CREDENTIALS_FILE" << EOF
[default]
aws_access_key_id = $ACCESS_KEY
aws_secret_access_key = $SECRET_KEY
aws_session_token = $SESSION_TOKEN
EOF

chmod 600 "$CREDENTIALS_FILE"

# Verify credentials work
echo "🔍 Verifying credentials..."
if IDENTITY=$(aws sts get-caller-identity 2>&1); then
    ACCOUNT=$(echo "$IDENTITY" | jq -r '.Account')
    ARN=$(echo "$IDENTITY" | jq -r '.Arn')
    
    echo -e "${GREEN}✅ Credentials refreshed successfully!${NC}"
    echo ""
    echo "   Account: $ACCOUNT"
    echo "   Identity: $ARN"
    echo "   Expires: $EXPIRES_AT"
    if [ -n "${REMAINING_MINS:-}" ]; then
        echo "   Time remaining: ~$REMAINING_MINS minutes"
    fi
    echo ""
    echo "   MCP servers can now authenticate with AWS."
else
    echo -e "${RED}❌ Error: Credentials were written but verification failed.${NC}"
    echo "   $IDENTITY"
    exit 1
fi

