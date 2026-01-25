#!/bin/bash

# Configuration - customize via environment variables
POD_NAME="${POD_NAME:-devcontainer-$(date +%s)}"
IMAGE="${IMAGE:-ghcr.io/kim-tae-kyung/code-devcontainer:latest}"

echo "Creating pod $POD_NAME..."

# Build overrides JSON conditionally
OVERRIDES=$(jq -n \
    --arg sa "$SERVICE_ACCOUNT" \
    --arg node "$NODE_NAME" \
    '{spec: {tolerations: [
        {key: "node-role.kubernetes.io/control-plane", operator: "Exists", effect: "NoSchedule"},
        {key: "node-role.kubernetes.io/master", operator: "Exists", effect: "NoSchedule"}
    ]}}
    | if $sa != "" then .spec.serviceAccountName = $sa else . end
    | if $node != "" then .spec.nodeName = $node else . end')

kubectl run "$POD_NAME" \
    --image="$IMAGE" \
    --image-pull-policy=IfNotPresent \
    ${NAMESPACE:+--namespace="$NAMESPACE"} \
    --overrides="$OVERRIDES" \
    -- sleep infinity

echo "Done! Connect: kubectl exec -it $POD_NAME ${NAMESPACE:+-n $NAMESPACE} -- /bin/bash"
