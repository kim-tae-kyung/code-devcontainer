#!/bin/bash

# Configuration variables - customize these for your environment
POD_NAME="${POD_NAME:-devcontainer-$(date +%s)}"
IMAGE="${IMAGE:-ghcr.io/kim-tae-kyung/code-devcontainer:latest}"
NAMESPACE="${NAMESPACE:-edgestack}"

echo "Creating devcontainer pod..."
echo "Pod name: $POD_NAME"
echo "Image: $IMAGE"
echo "Namespace: $NAMESPACE"
echo "Service account: provider-api"

# Run the devcontainer pod on control plane nodes
# - Runs on control plane nodes (useful for cluster administration tasks)
# - Uses tolerations to allow scheduling on master/control-plane nodes
# - Keeps running with 'sleep infinity' for interactive development
kubectl run $POD_NAME --image=$IMAGE --namespace=$NAMESPACE --overrides='
{
  "spec": {
    "serviceAccountName": "provider-api",
    "nodeSelector": {
      "node-role.kubernetes.io/control-plane": ""
    },
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
' --image-pull-policy=IfNotPresent -- sleep infinity

echo ""
echo "Pod created successfully!"
echo "To connect: kubectl exec -it $POD_NAME -n $NAMESPACE -- /bin/bash"
echo "To delete: kubectl delete pod $POD_NAME -n $NAMESPACE"

