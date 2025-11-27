#!/usr/bin/env bash
# =============================================================================
# refresh-aws-creds.sh
# =============================================================================
# Manages AWS credentials for MCP servers. Handles multiple auth scenarios:
#
# AUTHENTICATION METHODS:
# 1. Standard IAM credentials (aws configure) - Already works, no action needed
# 2. AWS SSO / Identity Center (aws login) - Needs credential extraction
# 3. Environment variables - Already works, no action needed
#
# USAGE:
#   ./scripts/refresh-aws-creds.sh          # Check credentials, extract SSO if needed
#   ./scripts/refresh-aws-creds.sh --check  # Just verify current credentials
#   ./scripts/refresh-aws-creds.sh --sso    # Force SSO credential extraction
#   ./scripts/refresh-aws-creds.sh --help   # Show this help
#
# PREREQUISITES:
#   - jq must be installed (for SSO extraction)
#   - For SSO: Run 'aws sso login' or 'aws login' first
#
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CREDENTIALS_FILE="$HOME/.aws/credentials"
SSO_CACHE_DIR="$HOME/.aws/sso/cache"
LOGIN_CACHE_DIR="$HOME/.aws/login/cache"

# =============================================================================
# Helper Functions
# =============================================================================

show_help() {
    cat << EOF
AWS Credentials Helper for MCP Servers

USAGE:
    ./scripts/refresh-aws-creds.sh [OPTIONS]

OPTIONS:
    --check     Just verify current credentials without making changes
    --sso       Force SSO credential extraction (overwrites existing credentials)
    --help      Show this help message

AUTHENTICATION METHODS:

  1. Standard IAM Credentials (RECOMMENDED for this lab)
     $ aws configure
     → Credentials stored in ~/.aws/credentials
     → MCP servers read them directly - no refresh needed!

  2. AWS SSO / Identity Center
     $ aws sso login --profile <profile>
     → Credentials cached in ~/.aws/sso/cache/
     → Run this script with --sso to extract for MCP servers

  3. Environment Variables
     $ export AWS_ACCESS_KEY_ID=...
     $ export AWS_SECRET_ACCESS_KEY=...
     → MCP servers read them directly - no refresh needed!

EXAMPLES:
    # Check if your credentials are working
    ./scripts/refresh-aws-creds.sh --check

    # Using standard IAM credentials (most common)
    aws configure
    ./scripts/refresh-aws-creds.sh --check  # Verify they work

    # Using AWS SSO
    aws sso login --profile my-sso-profile
    ./scripts/refresh-aws-creds.sh --sso    # Extract for MCP servers

EOF
    exit 0
}

check_jq() {
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}❌ Error: jq is required but not installed.${NC}"
        echo "   Install with: sudo apt-get install jq"
        exit 1
    fi
}

# Check if credentials file has non-temporary credentials (no session token)
has_persistent_credentials() {
    if [ ! -f "$CREDENTIALS_FILE" ]; then
        return 1
    fi
    
    # Check if there's an access key but NO session token (indicates long-lived creds)
    if grep -q "aws_access_key_id" "$CREDENTIALS_FILE" && \
       ! grep -q "aws_session_token" "$CREDENTIALS_FILE"; then
        return 0
    fi
    return 1
}

# Verify current credentials work
verify_credentials() {
    echo "🔍 Verifying AWS credentials..."
    
    if IDENTITY=$(aws sts get-caller-identity 2>&1); then
        ACCOUNT=$(echo "$IDENTITY" | jq -r '.Account')
        ARN=$(echo "$IDENTITY" | jq -r '.Arn')
        USER_ID=$(echo "$IDENTITY" | jq -r '.UserId')
        
        echo -e "${GREEN}✅ AWS credentials are valid!${NC}"
        echo ""
        echo "   Account:  $ACCOUNT"
        echo "   Identity: $ARN"
        echo "   User ID:  $USER_ID"
        
        # Determine credential type
        if [ -n "${AWS_ACCESS_KEY_ID:-}" ]; then
            echo -e "   Source:   ${BLUE}Environment variables${NC}"
        elif has_persistent_credentials; then
            echo -e "   Source:   ${BLUE}~/.aws/credentials (persistent IAM credentials)${NC}"
        else
            echo -e "   Source:   ${BLUE}~/.aws/credentials (temporary/SSO credentials)${NC}"
        fi
        
        echo ""
        echo -e "   ${GREEN}MCP servers can authenticate with AWS.${NC}"
        return 0
    else
        echo -e "${RED}❌ AWS credentials are NOT working.${NC}"
        echo ""
        echo "   Error: $IDENTITY"
        echo ""
        echo "   To fix this, either:"
        echo "   1. Run: aws configure"
        echo "   2. Or:  aws sso login --profile <profile>"
        echo ""
        return 1
    fi
}

# Extract SSO credentials from cache
extract_sso_credentials() {
    echo "🔄 Extracting SSO credentials for MCP servers..."
    echo ""
    
    check_jq
    
    # Try both SSO cache locations
    local CACHE_FILE=""
    
    # First try the newer sso/cache location
    if [ -d "$SSO_CACHE_DIR" ]; then
        CACHE_FILE=$(find "$SSO_CACHE_DIR" -name "*.json" -type f 2>/dev/null | while read -r f; do
            # Look for files with accessToken (not just the botocore cache)
            if jq -e '.accessToken' "$f" &>/dev/null 2>&1; then
                echo "$f"
                break
            fi
        done)
    fi
    
    # Fall back to login/cache
    if [ -z "$CACHE_FILE" ] && [ -d "$LOGIN_CACHE_DIR" ]; then
        CACHE_FILE=$(ls "$LOGIN_CACHE_DIR"/*.json 2>/dev/null | head -1)
    fi
    
    if [ -z "$CACHE_FILE" ] || [ ! -f "$CACHE_FILE" ]; then
        echo -e "${RED}❌ No SSO credentials found in cache.${NC}"
        echo ""
        echo "   Run one of these commands first:"
        echo "   $ aws sso login --profile <profile-name>"
        echo "   $ aws login"
        echo ""
        return 1
    fi
    
    echo "   Found cache: $CACHE_FILE"
    
    # Check expiration
    local EXPIRES_AT=$(jq -r '.expiresAt // .accessToken.expiresAt // empty' "$CACHE_FILE")
    if [ -n "$EXPIRES_AT" ]; then
        local EXPIRES_EPOCH=$(date -d "$EXPIRES_AT" +%s 2>/dev/null || echo "0")
        local NOW_EPOCH=$(date +%s)
        
        if [ "$EXPIRES_EPOCH" -lt "$NOW_EPOCH" ]; then
            echo -e "${RED}❌ SSO credentials have expired.${NC}"
            echo "   Expired at: $EXPIRES_AT"
            echo "   Run 'aws sso login' to refresh."
            return 1
        fi
        
        local REMAINING=$((EXPIRES_EPOCH - NOW_EPOCH))
        local REMAINING_MINS=$((REMAINING / 60))
        
        if [ "$REMAINING_MINS" -lt 5 ]; then
            echo -e "${YELLOW}⚠️  Warning: Credentials expire in $REMAINING_MINS minutes.${NC}"
        fi
    fi
    
    # Extract credentials (try both formats)
    local ACCESS_KEY=$(jq -r '.accessToken.accessKeyId // .Credentials.AccessKeyId // empty' "$CACHE_FILE")
    local SECRET_KEY=$(jq -r '.accessToken.secretAccessKey // .Credentials.SecretAccessKey // empty' "$CACHE_FILE")
    local SESSION_TOKEN=$(jq -r '.accessToken.sessionToken // .Credentials.SessionToken // empty' "$CACHE_FILE")
    
    if [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ]; then
        echo -e "${RED}❌ Could not extract credentials from cache file.${NC}"
        echo "   The cache format may not be supported."
        return 1
    fi
    
    # Warn if overwriting persistent credentials
    if has_persistent_credentials; then
        echo ""
        echo -e "${YELLOW}⚠️  WARNING: You have persistent IAM credentials that will be overwritten!${NC}"
        echo "   These are typically long-lived credentials from 'aws configure'."
        echo ""
        read -p "   Continue and overwrite? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "   Aborted. Your credentials were not changed."
            return 1
        fi
    fi
    
    # Write credentials
    cat > "$CREDENTIALS_FILE" << EOF
[default]
aws_access_key_id = $ACCESS_KEY
aws_secret_access_key = $SECRET_KEY
aws_session_token = $SESSION_TOKEN
# Source: SSO credentials extracted by refresh-aws-creds.sh
# Expires: ${EXPIRES_AT:-unknown}
EOF
    
    chmod 600 "$CREDENTIALS_FILE"
    
    echo ""
    echo -e "${GREEN}✅ SSO credentials extracted successfully!${NC}"
    if [ -n "${EXPIRES_AT:-}" ]; then
        echo "   Expires: $EXPIRES_AT"
        if [ -n "${REMAINING_MINS:-}" ]; then
            echo "   Time remaining: ~$REMAINING_MINS minutes"
        fi
    fi
    echo ""
    
    # Verify
    verify_credentials
}

# =============================================================================
# Main Logic
# =============================================================================

main() {
    local MODE="auto"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --check)
                MODE="check"
                shift
                ;;
            --sso)
                MODE="sso"
                shift
                ;;
            --help|-h)
                show_help
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                echo "Use --help for usage information."
                exit 1
                ;;
        esac
    done
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  AWS Credentials Helper for MCP Servers"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    case $MODE in
        check)
            # Just verify credentials
            if verify_credentials; then
                exit 0
            else
                exit 1
            fi
            ;;
        sso)
            # Force SSO extraction
            extract_sso_credentials
            ;;
        auto)
            # Auto-detect: if credentials work, just report. Otherwise try SSO.
            echo "🔍 Checking current AWS credentials..."
            echo ""
            
            if verify_credentials; then
                echo ""
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo -e "  ${GREEN}No action needed - credentials are working!${NC}"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                exit 0
            else
                echo ""
                echo "   Attempting to extract SSO credentials..."
                echo ""
                extract_sso_credentials
            fi
            ;;
    esac
}

main "$@"
