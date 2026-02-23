#!/usr/bin/env bash
# Quick setup script for Claude Code container

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Claude Code Container Setup${NC}"
echo ""

# Check if running in Nix environment
if ! command -v nix &> /dev/null; then
    echo -e "${RED}Error: Nix is not installed or not in PATH${NC}"
    exit 1
fi

# Parse command line arguments
REGISTRY=""
TAG="latest"

while [[ $# -gt 0 ]]; do
    case $1 in
        --registry)
            REGISTRY="$2"
            shift 2
            ;;
        --tag)
            TAG="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --registry REGISTRY  Container registry URL (e.g., registry.example.com/user)"
            echo "  --tag TAG           Image tag (default: latest)"
            echo "  --help              Show this help message"
            echo ""
            echo "Example:"
            echo "  $0 --registry myregistry.com/myuser --tag v1.0.0"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Step 1: Build the container
echo -e "${YELLOW}Step 1: Building container image...${NC}"
nix build .#container

if [ ! -f result ]; then
    echo -e "${RED}Error: Build failed, result file not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Container built successfully${NC}"
echo ""

# Step 2: Load into podman
echo -e "${YELLOW}Step 2: Loading into podman...${NC}"
IMAGE_NAME=$(podman load < result | grep -oP 'Loaded image: \K.*')

if [ -z "$IMAGE_NAME" ]; then
    echo -e "${RED}Error: Failed to load image into podman${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Loaded as: $IMAGE_NAME${NC}"
echo ""

# Step 3: Tag and push if registry specified
if [ -n "$REGISTRY" ]; then
    FULL_IMAGE="$REGISTRY/claude-code-server:$TAG"

    echo -e "${YELLOW}Step 3: Tagging and pushing to registry...${NC}"
    podman tag "$IMAGE_NAME" "$FULL_IMAGE"
    echo -e "Tagged as: $FULL_IMAGE"

    echo "Pushing to registry..."
    podman push "$FULL_IMAGE"

    echo -e "${GREEN}✓ Pushed to registry${NC}"
    echo ""

    # Step 4: Update k8s manifest
    echo -e "${YELLOW}Step 4: Updating Kubernetes manifest...${NC}"
    sed -i "s|image:.*|image: $FULL_IMAGE|" k8s-deployment.yaml
    echo -e "${GREEN}✓ Updated k8s-deployment.yaml${NC}"
    echo ""
fi

# Setup SSH keys
echo -e "${YELLOW}Setting up SSH keys for Kubernetes...${NC}"
echo ""
echo "Create the ConfigMap with your SSH public key:"
echo -e "${GREEN}kubectl create configmap claude-ssh-keys --from-file=authorized_keys=~/.ssh/id_rsa.pub${NC}"
echo ""

# Apply Kubernetes manifests
if [ -n "$REGISTRY" ]; then
    echo -e "${YELLOW}Deploy to Kubernetes:${NC}"
    echo -e "${GREEN}kubectl apply -f k8s-deployment.yaml${NC}"
    echo ""
    echo -e "${YELLOW}Get service IP:${NC}"
    echo -e "${GREEN}kubectl get svc claude-code-server${NC}"
    echo ""
    echo -e "${YELLOW}Connect:${NC}"
    echo -e "${GREEN}ssh -p 2222 claude@<EXTERNAL-IP>${NC}"
fi

# Local testing instructions
echo ""
echo -e "${YELLOW}For local testing:${NC}"
echo ""
echo "1. Create directories:"
echo -e "   ${GREEN}mkdir -p ssh-keys claude-home${NC}"
echo ""
echo "2. Copy your public key:"
echo -e "   ${GREEN}cp ~/.ssh/id_rsa.pub ssh-keys/authorized_keys${NC}"
echo ""
echo "3. Run container:"
echo -e "   ${GREEN}podman run -d --name claude-code -p 2222:2222 -v ./claude-home:/home/claude -v ./ssh-keys:/ssh-keys:ro $IMAGE_NAME${NC}"
echo ""
echo "4. Connect:"
echo -e "   ${GREEN}ssh -p 2222 claude@localhost${NC}"
echo ""

echo -e "${GREEN}Setup complete!${NC}"
