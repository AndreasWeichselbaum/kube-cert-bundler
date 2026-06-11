#!/bin/bash

set -e

# Usage
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    cat << EOF
Usage: $0 BUNDLE_PATH [KUBECONFIG_PATH]

Extract cluster CA certificates from kubeconfig and append a certificate bundle to each.

Arguments:
  BUNDLE_PATH        Path to certificate bundle to append (mandatory)
  KUBECONFIG_PATH    Path to kubeconfig file (default: \$KUBECONFIG or ~/.kube/config)

Examples:
  $0 /path/to/bundle.pem                                # Use bundle and default kubeconfig
  $0 /path/to/bundle.pem /etc/kubeconfig                # Use both custom paths

Behavior:
  - Extracts cluster CA certificates to the same directory as the kubeconfig
  - Appends the certificate bundle to each CA file
  - Updates kubeconfig to reference the certificate files instead of inline data
  - Idempotent: skips clusters already using file-based certificates
EOF
    exit 0
fi

if [ $# -eq 0 ]; then
    echo "Error: BUNDLE_PATH is required"
    echo "Run: $0 --help"
    exit 1
fi

# Parameters
BUNDLE_PATH="${1}"
KUBECONFIG_PATH="${2:-${KUBECONFIG:-$HOME/.kube/config}}"
KUBE_DIR="$(dirname "$KUBECONFIG_PATH")"

# Validate prerequisites
if [ ! -f "$BUNDLE_PATH" ]; then
    echo "Error: certificate bundle not found at $BUNDLE_PATH"
    exit 1
fi

if [ ! -f "$KUBECONFIG_PATH" ]; then
    echo "Error: kubeconfig not found at $KUBECONFIG_PATH"
    exit 1
fi

if [ ! -d "$KUBE_DIR" ]; then
    mkdir -p "$KUBE_DIR"
fi

# Get all cluster names from kubeconfig
CLUSTERS=$(kubectl config get-clusters --kubeconfig="$KUBECONFIG_PATH" | tail -n +2 | grep -v '^$')

if [ -z "$CLUSTERS" ]; then
    echo "No clusters found in kubeconfig"
    exit 0
fi

echo "Found clusters:"
echo "$CLUSTERS" | sed 's/^/  - /'
echo ""

while IFS= read -r cluster; do
    echo "Processing cluster: $cluster"

    # Create PEM file path
    PEM_FILE="$KUBE_DIR/${cluster}-ca.pem"

    # Extract CA data using kubectl (without --flatten to avoid file access errors)
    CA_DATA=$(kubectl config view --kubeconfig="$KUBECONFIG_PATH" --raw \
        -o jsonpath="{.clusters[?(@.name=='$cluster')].cluster.certificate-authority-data}" 2>/dev/null)

    # Check if already processed: PEM file exists and kubeconfig points to it (not using inline data)
    if [ -f "$PEM_FILE" ] && [ -z "$CA_DATA" ]; then
        echo "  ⊘ Already processed, skipping"
        continue
    fi

    if [ -z "$CA_DATA" ]; then
        # Try reading from certificate-authority file path if inline data doesn't exist
        CA_FILE=$(kubectl config view --kubeconfig="$KUBECONFIG_PATH" --raw \
            -o jsonpath="{.clusters[?(@.name=='$cluster')].cluster.certificate-authority}" 2>/dev/null)

        if [ -n "$CA_FILE" ] && [ -f "$CA_FILE" ]; then
            echo "  ℹ Reading CA from file: $CA_FILE"
            CA_DATA=$(cat "$CA_FILE" | base64)
        else
            echo "  ⚠ Warning: No certificate-authority-data or file found for cluster $cluster, skipping"
            continue
        fi
    fi

    # Decode base64 CA data and save to PEM file
    echo "$CA_DATA" | base64 -d > "$PEM_FILE"
    chmod 644 "$PEM_FILE"

    # Append certificate bundle
    echo "" >> "$PEM_FILE"
    cat "$BUNDLE_PATH" >> "$PEM_FILE"

    echo "  ✓ Created: $PEM_FILE"

    # Update kubeconfig to use the file path
    kubectl config set clusters."${cluster}".certificate-authority "$PEM_FILE" \
        --kubeconfig="$KUBECONFIG_PATH"

    # Remove the inline certificate-authority-data
    kubectl config unset clusters."${cluster}".certificate-authority-data \
        --kubeconfig="$KUBECONFIG_PATH"

    echo "  ✓ Updated kubeconfig for cluster $cluster"

done <<< "$CLUSTERS"

echo ""
echo "✓ Done! All clusters have been updated:"
echo "  - CA certificates extracted to $KUBE_DIR"
echo "  - Certificate bundle appended to each CA file"
echo "  - kubeconfig updated to reference certificate files"