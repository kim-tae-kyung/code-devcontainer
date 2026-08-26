#!/bin/bash
set -e

# Example: NODE_NAME=master0 NAMESPACE=kube-system ./run-k8s-daemon-example.sh
# Environment variables: POD_NAME, IMAGE, NAMESPACE, SERVICE_ACCOUNT, NODE_NAME

POD_NAME="${POD_NAME:-devcontainer-$(date +%s)}"
IMAGE="${IMAGE:-ghcr.io/kim-tae-kyung/code-devcontainer:latest}"

echo "Creating pod $POD_NAME..."

OVERRIDES=$(jq -n \
    --arg sa "$SERVICE_ACCOUNT" \
    --arg node "$NODE_NAME" \
    '{spec: {shareProcessNamespace: true, tolerations: [
        {key: "node-role.kubernetes.io/control-plane", operator: "Exists", effect: "NoSchedule"},
        {key: "node-role.kubernetes.io/master", operator: "Exists", effect: "NoSchedule"}
    ]}}
    * (if $sa != "" then {spec: {serviceAccountName: $sa}} else {} end)
    * (if $node != "" then {spec: {nodeName: $node}} else {} end)')

NS_FLAG="${NAMESPACE:+--namespace=$NAMESPACE}"

# Always: the default tag is mutable `latest`, and a node-cached copy would
# otherwise pin the pod to a stale weekly build. The image CMD keeps it alive.
kubectl run "$POD_NAME" \
    --image="$IMAGE" \
    --image-pull-policy=Always \
    ${NS_FLAG} \
    --overrides="$OVERRIDES"

echo "Waiting for pod to be ready..."
kubectl wait --for=condition=Ready "pod/$POD_NAME" ${NS_FLAG} --timeout=600s

copy_private_file() {
    local source_path="$1"
    local destination_path="$2"
    local description="$3"
    local destination_dir="${4:-}"

    if [ ! -f "$source_path" ]; then
        return
    fi

    echo "Copying $description..."
    if [ -n "$destination_dir" ]; then
        kubectl exec ${NS_FLAG} "$POD_NAME" -- install -d -m 700 "$destination_dir"
    fi
    kubectl cp "$source_path" "${POD_NAME}:${destination_path}" ${NS_FLAG}
    kubectl exec ${NS_FLAG} "$POD_NAME" -- chmod 600 "$destination_path"
}

if [ -d "${HOME}/.ssh" ]; then
    echo "Copying SSH keys..."
    kubectl cp "${HOME}/.ssh" "${POD_NAME}:/home/node/.ssh" ${NS_FLAG}
    # Restrict the directory and private key permissions after copying.
    kubectl exec ${NS_FLAG} "$POD_NAME" -- sh -c 'chmod 700 /home/node/.ssh && find /home/node/.ssh -type f ! -name "*.pub" -exec chmod 600 {} +'
fi

copy_private_file "${HOME}/.gitconfig" "/home/node/.gitconfig" "Git configuration"
copy_private_file "${HOME}/.config/gh/hosts.yml" "/home/node/.config/gh/hosts.yml" "GitHub CLI credentials" "/home/node/.config/gh"
copy_private_file "${HOME}/.claude/.credentials.json" "/home/node/.claude/.credentials.json" "Claude Code credentials" "/home/node/.claude"
copy_private_file "${HOME}/.codex/auth.json" "/home/node/.codex/auth.json" "Codex credentials" "/home/node/.codex"

echo "Done! Connect: kubectl exec -it $POD_NAME ${NS_FLAG} -- /bin/bash"
