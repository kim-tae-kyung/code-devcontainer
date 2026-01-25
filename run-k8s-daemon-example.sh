#!/bin/bash

set -e

# Configuration variables - customize these for your environment
POD_NAME="${POD_NAME:-devcontainer-$(date +%s)}"
IMAGE="${IMAGE:-ghcr.io/kim-tae-kyung/code-devcontainer:latest}"
NAMESPACE="${NAMESPACE:-edgestack}"
SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-provider-api}"
NODE_NAME="${NODE_NAME:-}"
IMAGE_PULL_POLICY="${IMAGE_PULL_POLICY:-IfNotPresent}"

# Display help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Create a devcontainer pod in Kubernetes for interactive development.

Environment Variables:
  POD_NAME           Pod name (default: devcontainer-<timestamp>)
  IMAGE              Container image (default: ghcr.io/kim-tae-kyung/code-devcontainer:latest)
  NAMESPACE          Kubernetes namespace (default: edgestack)
  SERVICE_ACCOUNT    Service account name (default: provider-api)
  NODE_NAME          Target node name (required - use 'kubectl get nodes' to list)
  IMAGE_PULL_POLICY  Image pull policy (default: IfNotPresent)

Examples:
  # Basic usage with required node name
  NODE_NAME=worker-1 $0

  # Full customization
  POD_NAME=my-dev NODE_NAME=worker-1 NAMESPACE=dev SERVICE_ACCOUNT=admin $0

  # List available nodes
  kubectl get nodes
EOF
}

# Parse arguments
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# Validate required parameters
if [[ -z "$NODE_NAME" ]]; then
    echo "Error: NODE_NAME environment variable is required."
    echo "Use 'kubectl get nodes' to list available nodes."
    echo "Run '$0 --help' for more information."
    exit 1
fi

echo "Creating devcontainer pod..."
echo "  Pod name:        $POD_NAME"
echo "  Image:           $IMAGE"
echo "  Namespace:       $NAMESPACE"
echo "  Service account: $SERVICE_ACCOUNT"
echo "  Node:            $NODE_NAME"
echo "  Pull policy:     $IMAGE_PULL_POLICY"
echo ""

# Build the pod spec with overrides
OVERRIDES=$(cat <<EOF
{
  "spec": {
    "serviceAccountName": "$SERVICE_ACCOUNT",
    "nodeName": "$NODE_NAME",
    "tolerations": [
      {
        "key": "node-role.kubernetes.io/control-plane",
        "operator": "Exists",
        "effect": "NoSchedule"
      },
      {
        "key": "node-role.kubernetes.io/master",
        "operator": "Exists",
        "effect": "NoSchedule"
      }
    ]
  }
}
EOF
)

# Run the devcontainer pod
# - Schedules on the specified node
# - Uses tolerations to allow scheduling on master/control-plane nodes
# - Keeps running with 'sleep infinity' for interactive development
kubectl run "$POD_NAME" \
    --image="$IMAGE" \
    --namespace="$NAMESPACE" \
    --image-pull-policy="$IMAGE_PULL_POLICY" \
    --overrides="$OVERRIDES" \
    -- sleep infinity

echo ""
echo "Pod created successfully!"
echo ""
echo "Useful commands:"
echo "  Connect:  kubectl exec -it $POD_NAME -n $NAMESPACE -- /bin/bash"
echo "  Status:   kubectl get pod $POD_NAME -n $NAMESPACE"
echo "  Logs:     kubectl logs $POD_NAME -n $NAMESPACE"
echo "  Delete:   kubectl delete pod $POD_NAME -n $NAMESPACE"

