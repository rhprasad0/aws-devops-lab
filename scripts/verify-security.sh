#!/bin/bash
# Verify Week 0 Security Baseline Services

set -e

echo "🔍 Verifying Security Baseline Services..."

# Check GuardDuty
echo "📡 Checking GuardDuty..."
GUARDDUTY_ID=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text --region us-east-1)
if [ "$GUARDDUTY_ID" != "None" ] && [ "$GUARDDUTY_ID" != "" ]; then
    echo "✅ GuardDuty enabled: $GUARDDUTY_ID"
    aws guardduty get-detector --detector-id "$GUARDDUTY_ID" --query 'Status' --output text --region us-east-1
else
    echo "❌ GuardDuty not found"
fi

# Check Config
echo "📋 Checking Config..."
CONFIG_STATUS=$(aws configservice describe-configuration-recorders --query 'ConfigurationRecorders[0].recordingGroup.allSupported' --output text --region us-east-1 2>/dev/null || echo "None")
if [ "$CONFIG_STATUS" != "None" ]; then
    echo "✅ Config enabled"
    aws configservice describe-configuration-recorder-status --query 'ConfigurationRecordersStatus[0].recording' --output text --region us-east-1
else
    echo "❌ Config not found"
fi

# Check Security Hub
echo "🛡️  Checking Security Hub..."
SECURITYHUB_STATUS=$(aws securityhub describe-hub --query 'HubArn' --output text --region us-east-1 2>/dev/null || echo "None")
if [ "$SECURITYHUB_STATUS" != "None" ]; then
    echo "✅ Security Hub enabled"
    echo "   ARN: $SECURITYHUB_STATUS"
else
    echo "❌ Security Hub not found"
fi

echo ""
echo "🎯 Security Baseline Status Complete!"
echo "💡 Note: It takes 24-48 hours for these services to populate with findings."
