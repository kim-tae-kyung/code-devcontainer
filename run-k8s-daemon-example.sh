#!/bin/bash

# Example: NODE_NAME=master0 NAMESPACE=kube-system ./run-k8s-daemon-example.sh
# Environment variables: POD_NAME, IMAGE, NAMESPACE, SERVICE_ACCOUNT, NODE_NAME

POD_NAME="${POD_NAME:-devcontainer-$(date +%s)}"
IMAGE="${IMAGE:-ghcr.io/kim-tae-kyung/code-devcontainer:latest}"

echo "Creating pod $POD_NAME..."

OVERRIDES=$(jq -n \
    --arg sa "$SERVICE_ACCOUNT" \
    --arg node "$NODE_NAME" \
    '{spec: {tolerations: [
        {key: "node-role.kubernetes.io/control-plane", operator: "Exists", effect: "NoSchedule"},
        {key: "node-role.kubernetes.io/master", operator: "Exists", effect: "NoSchedule"}
    ]}}
    * (if $sa != "" then {spec: {serviceAccountName: $sa}} else {} end)
    * (if $node != "" then {spec: {nodeName: $node}} else {} end)')

NS_FLAG="${NAMESPACE:+--namespace=$NAMESPACE}"

kubectl run "$POD_NAME" \
    --image="$IMAGE" \
    --image-pull-policy=IfNotPresent \
    ${NS_FLAG} \
    --overrides="$OVERRIDES" \
    -- sleep infinity

echo "Waiting for pod to be ready..."
kubectl wait --for=condition=Ready "pod/$POD_NAME" ${NS_FLAG} --timeout=120s

if [ -d "${HOME}/.ssh" ]; then
    echo "Copying SSH keys..."
    kubectl cp "${HOME}/.ssh" "${POD_NAME}:/home/node/.ssh" ${NS_FLAG}
    kubectl exec ${NS_FLAG} "$POD_NAME" -- chmod 700 /home/node/.ssh
    kubectl exec ${NS_FLAG} "$POD_NAME" -- sh -c 'chmod 600 /home/node/.ssh/*'
fi

echo "Done! Connect: kubectl exec -it $POD_NAME ${NS_FLAG} -- /bin/bash"
