#!/bin/bash

# Configuration - customize via environment variables
POD_NAME="${POD_NAME:-devcontainer-$(date +%s)}"
IMAGE="${IMAGE:-ghcr.io/kim-tae-kyung/code-devcontainer:latest}"
NAMESPACE="${NAMESPACE:-edgestack}"
SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-provider-api}"
NODE_NAME="${NODE_NAME:?Error: NODE_NAME is required}"

echo "Creating pod $POD_NAME on node $NODE_NAME..."

kubectl run "$POD_NAME" \
    --image="$IMAGE" \
    --namespace="$NAMESPACE" \
    --image-pull-policy=IfNotPresent \
    --overrides='{
      "spec": {
        "serviceAccountName": "'"$SERVICE_ACCOUNT"'",
        "nodeName": "'"$NODE_NAME"'",
        "tolerations": [
          {"key": "node-role.kubernetes.io/control-plane", "operator": "Exists", "effect": "NoSchedule"},
          {"key": "node-role.kubernetes.io/master", "operator": "Exists", "effect": "NoSchedule"}
        ]
      }
    }' \
    -- sleep infinity

echo "Done! Connect: kubectl exec -it $POD_NAME -n $NAMESPACE -- /bin/bash"
