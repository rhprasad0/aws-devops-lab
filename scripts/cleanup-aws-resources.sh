#!/bin/bash
set -e

echo "🧹 Enhanced cleanup of AWS resources that block Terraform destroy..."

# Get cluster name and region from Terraform
CLUSTER_NAME=$(cd infra && terraform output -raw cluster_name 2>/dev/null || echo "dev-eks")
REGION=$(cd infra && terraform output -raw region 2>/dev/null || echo "us-east-1")
VPC_ID=$(cd infra && terraform output -raw vpc_id 2>/dev/null || echo "")

echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo "VPC: $VPC_ID"

# 1. Delete ALL load balancers in the VPC (not just k8s- prefixed)
if [ -n "$VPC_ID" ]; then
    echo "🔍 Looking for ALL load balancers in VPC $VPC_ID..."
    ALB_ARNS=$(aws elbv2 describe-load-balancers --region $REGION --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" --output text 2>/dev/null || true)
    
    if [ -n "$ALB_ARNS" ] && [ "$ALB_ARNS" != "None" ]; then
        echo "🗑️  Deleting load balancers..."
        for arn in $ALB_ARNS; do
            echo "  Deleting LB: $arn"
            aws elbv2 delete-load-balancer --load-balancer-arn "$arn" --region $REGION || true
        done
        echo "⏳ Waiting 60s for load balancer deletion..."
        sleep 60
    else
        echo "✅ No load balancers found in VPC"
    fi
fi

# 2. Delete ALL target groups in the VPC
if [ -n "$VPC_ID" ]; then
    echo "🔍 Looking for ALL target groups in VPC $VPC_ID..."
    TG_ARNS=$(aws elbv2 describe-target-groups --region $REGION --query "TargetGroups[?VpcId=='$VPC_ID'].TargetGroupArn" --output text 2>/dev/null || true)
    
    if [ -n "$TG_ARNS" ] && [ "$TG_ARNS" != "None" ]; then
        echo "🗑️  Deleting target groups..."
        for arn in $TG_ARNS; do
            echo "  Deleting TG: $arn"
            aws elbv2 delete-target-group --target-group-arn "$arn" --region $REGION || true
        done
    else
        echo "✅ No target groups found in VPC"
    fi
fi

# 3. Delete ALL non-default security groups in VPC
if [ -n "$VPC_ID" ]; then
    echo "🔍 Looking for non-default security groups in VPC $VPC_ID..."
    SG_IDS=$(aws ec2 describe-security-groups --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text 2>/dev/null || true)
    
    if [ -n "$SG_IDS" ] && [ "$SG_IDS" != "None" ]; then
        echo "🗑️  Deleting security groups..."
        # Delete in multiple passes to handle dependencies
        for pass in 1 2 3; do
            echo "  Pass $pass..."
            for sg_id in $SG_IDS; do
                aws ec2 delete-security-group --group-id "$sg_id" --region $REGION 2>/dev/null || true
            done
            sleep 5
        done
    else
        echo "✅ No non-default security groups found"
    fi
fi

# 4. Delete ALL network interfaces in VPC (available and in-use)
if [ -n "$VPC_ID" ]; then
    echo "🔍 Looking for ALL network interfaces in VPC $VPC_ID..."
    
    # First, detach and delete available ENIs
    ENI_IDS=$(aws ec2 describe-network-interfaces --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" "Name=status,Values=available" --query "NetworkInterfaces[].NetworkInterfaceId" --output text 2>/dev/null || true)
    
    if [ -n "$ENI_IDS" ] && [ "$ENI_IDS" != "None" ]; then
        echo "🗑️  Deleting available ENIs..."
        for eni_id in $ENI_IDS; do
            echo "  Deleting ENI: $eni_id"
            aws ec2 delete-network-interface --network-interface-id "$eni_id" --region $REGION || true
        done
    fi
    
    # Then, force detach in-use ENIs (except primary instance ENIs)
    INUSE_ENI_IDS=$(aws ec2 describe-network-interfaces --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" "Name=status,Values=in-use" --query "NetworkInterfaces[?Attachment.DeviceIndex!=\`0\`].NetworkInterfaceId" --output text 2>/dev/null || true)
    
    if [ -n "$INUSE_ENI_IDS" ] && [ "$INUSE_ENI_IDS" != "None" ]; then
        echo "🗑️  Force detaching and deleting in-use ENIs..."
        for eni_id in $INUSE_ENI_IDS; do
            echo "  Force detaching ENI: $eni_id"
            # Get attachment ID
            ATTACHMENT_ID=$(aws ec2 describe-network-interfaces --region $REGION --network-interface-ids "$eni_id" --query "NetworkInterfaces[0].Attachment.AttachmentId" --output text 2>/dev/null || true)
            if [ -n "$ATTACHMENT_ID" ] && [ "$ATTACHMENT_ID" != "None" ]; then
                aws ec2 detach-network-interface --attachment-id "$ATTACHMENT_ID" --force --region $REGION || true
                sleep 5
                aws ec2 delete-network-interface --network-interface-id "$eni_id" --region $REGION || true
            fi
        done
    fi
    
    echo "⏳ Waiting 30s for ENI cleanup..."
    sleep 30
fi

# 5. Release any Elastic IPs in the VPC
if [ -n "$VPC_ID" ]; then
    echo "🔍 Looking for Elastic IPs in VPC $VPC_ID..."
    EIP_ALLOC_IDS=$(aws ec2 describe-addresses --region $REGION --filters "Name=domain,Values=vpc" --query "Addresses[].AllocationId" --output text 2>/dev/null || true)
    
    if [ -n "$EIP_ALLOC_IDS" ] && [ "$EIP_ALLOC_IDS" != "None" ]; then
        echo "🗑️  Releasing Elastic IPs..."
        for alloc_id in $EIP_ALLOC_IDS; do
            echo "  Releasing EIP: $alloc_id"
            aws ec2 release-address --allocation-id "$alloc_id" --region $REGION || true
        done
    else
        echo "✅ No Elastic IPs found"
    fi
fi

echo "✅ Enhanced AWS resource cleanup complete!"
echo "💡 Now run 'terraform destroy' again"
