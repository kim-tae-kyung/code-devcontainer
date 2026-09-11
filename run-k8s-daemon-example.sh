#!/bin/bash
set -euo pipefail

# Example: NODE_NAME=master0 NAMESPACE=kube-system ./run-k8s-daemon-example.sh
# Environment variables: POD_NAME, IMAGE, NAMESPACE, SERVICE_ACCOUNT, NODE_NAME

POD_NAME="${POD_NAME:-devcontainer-$(date +%s)}"
IMAGE="${IMAGE:-ghcr.io/kim-tae-kyung/code-devcontainer:latest}"

echo "Creating pod $POD_NAME..."

OVERRIDES=$(jq -n \
    --arg sa "${SERVICE_ACCOUNT:-}" \
    --arg node "${NODE_NAME:-}" \
    '{spec: {shareProcessNamespace: true, tolerations: [
        {key: "node-role.kubernetes.io/control-plane", operator: "Exists", effect: "NoSchedule"},
        {key: "node-role.kubernetes.io/master", operator: "Exists", effect: "NoSchedule"}
    ]}}
    * (if $sa != "" then {spec: {serviceAccountName: $sa}} else {} end)
    * (if $node != "" then {spec: {nodeName: $node}} else {} end)')

namespace_flag="${NAMESPACE:+--namespace=$NAMESPACE}"

# Always: the default tag is mutable `latest`, and a node-cached copy would
# otherwise pin the pod to a stale weekly build. The image CMD keeps it alive.
kubectl run "$POD_NAME" \
    --image="$IMAGE" \
    --image-pull-policy=Always \
    ${namespace_flag:+"$namespace_flag"} \
    --overrides="$OVERRIDES"

echo "Waiting for pod to be ready..."
kubectl wait --for=condition=Ready "pod/$POD_NAME" ${namespace_flag:+"$namespace_flag"} --timeout=600s

if [ -d "${HOME}/.ssh" ]; then
    echo "Copying SSH configuration and keys..."
    kubectl exec "$POD_NAME" ${namespace_flag:+"$namespace_flag"} -- install -d -m 700 /home/node/.ssh
    # Copy into the parent so an existing .ssh directory is merged, not nested.
    kubectl cp "${HOME}/.ssh" "${POD_NAME}:/home/node/" ${namespace_flag:+"$namespace_flag"}
    kubectl exec "$POD_NAME" ${namespace_flag:+"$namespace_flag"} -- sh -c \
        'find /home/node/.ssh -type d -exec chmod 700 {} + && find /home/node/.ssh -type f -exec chmod 600 {} +'
fi

if [ -f "${HOME}/.gitconfig" ]; then
    echo "Copying Git configuration..."
    # Stream the contents so a dotfiles symlink also becomes a usable file.
    kubectl exec -i "$POD_NAME" ${namespace_flag:+"$namespace_flag"} -- sh -c \
        'umask 077; cat > /home/node/.gitconfig' < "${HOME}/.gitconfig"
    kubectl exec "$POD_NAME" ${namespace_flag:+"$namespace_flag"} -- chmod 600 /home/node/.gitconfig
fi

printf 'Done! Connect:'
printf ' %q' kubectl exec -it "$POD_NAME" ${namespace_flag:+"$namespace_flag"} -- herdr
printf '\n'
