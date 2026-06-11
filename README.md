# kube-cert-bundler

A utility script to bundle custom CA certificates with Kubernetes cluster certificates in your kubeconfig.

## Purpose

This script automates the process of injecting a custom Certificate Authority (CA) bundle into all Kubernetes clusters defined in your kubeconfig. This is useful when you need to authenticate to clusters through a corporate proxy, internal CA, or custom certificate chain.

Instead of manually managing certificate chains or dealing with SSL verification errors, this tool:
- Extracts each cluster's CA certificate from your kubeconfig
- Appends your custom CA bundle to each certificate file
- Updates the kubeconfig to reference the bundled certificate files

This allows you to use `kubectl` via HTTPS even behind a proxy or with a trusted MITM (man-in-the-middle) CA.

## Installation

Clone or download the script and make it executable:

```bash
chmod +x bundle-kube-certs.sh
```

No additional dependencies required beyond standard Unix tools and `kubectl` (which you already have if you use Kubernetes).

## Usage

### Basic syntax

```bash
./bundle-kube-certs.sh BUNDLE_PATH [KUBECONFIG_PATH]
```

### Arguments

- **BUNDLE_PATH** (required): Path to your certificate bundle file (typically a `.pem` file containing one or more CA certificates)
- **KUBECONFIG_PATH** (optional): Path to your kubeconfig file. Defaults to `$KUBECONFIG` environment variable, or `~/.kube/config` if not set

### Examples

```bash
# Use custom bundle with default kubeconfig (~/.kube/config)
./bundle-kube-certs.sh /path/to/ca-bundle.pem

# Use custom bundle and custom kubeconfig
./bundle-kube-certs.sh /path/to/ca-bundle.pem /etc/kubernetes/config

# Use KUBECONFIG environment variable
export KUBECONFIG=/custom/path/config
./bundle-kube-certs.sh /path/to/ca-bundle.pem
```

### Display help

```bash
./bundle-kube-certs.sh --help
```

## How it works

1. **Validation**: Checks that the bundle file and kubeconfig both exist
2. **Discovery**: Lists all clusters defined in your kubeconfig
3. **For each cluster**:
   - Extracts the cluster's CA certificate (from inline `certificate-authority-data` or from a `certificate-authority` file reference)
   - Saves it to a `.pem` file in the same directory as your kubeconfig (named `{cluster-name}-ca.pem`)
   - Prepends your custom CA bundle, followed by the cluster's original CA
   - Updates the kubeconfig to reference the new `.pem` file instead of inline certificate data
   - Removes the inline certificate data from kubeconfig

## Key features

### Idempotent
The script skips clusters that have already been processed (detected by checking if the `.pem` file exists and the kubeconfig already references it as a file). This means you can safely run it multiple times without duplicating CA bundles.

### Flexible input
Handles both:
- Inline certificates (base64-encoded in kubeconfig as `certificate-authority-data`)
- File-referenced certificates (kubeconfig pointing to a `certificate-authority` file path)

### Non-destructive
- Original kubeconfig is backed up implicitly by `kubectl config` commands
- The script creates new `.pem` files rather than modifying existing ones
- Inline certificate data is preserved in the extracted `.pem` file before appending the bundle

## Example workflow

Suppose you have two clusters in your kubeconfig and a corporate CA bundle:

```bash
./bundle-kube-certs.sh /etc/ssl/certs/corporate-ca-bundle.pem
```

Output:
```
Found clusters:
  - prod-cluster
  - staging-cluster

Processing cluster: prod-cluster
  ✓ Created: ~/.kube/prod-cluster-ca.pem
  ✓ Updated kubeconfig for cluster prod-cluster

Processing cluster: staging-cluster
  ✓ Created: ~/.kube/staging-cluster-ca.pem
  ✓ Updated kubeconfig for cluster staging-cluster

✓ Done! All clusters have been updated:
  - CA certificates extracted to ~/.kube
  - Certificate bundle appended to each CA file
  - kubeconfig updated to reference certificate files
```

After running this, your kubeconfig now references:
- `~/.kube/prod-cluster-ca.pem` (contains corporate bundle + original CA)
- `~/.kube/staging-cluster-ca.pem` (contains corporate bundle + original CA)

## Requirements

- Bash shell
- `kubectl` CLI (v1.x)
- Read and write access to your kubeconfig file
- Read access to the certificate bundle file
- Write access to the directory containing your kubeconfig (to create the `.pem` files)

## Troubleshooting

### Script says "No clusters found in kubeconfig"
Your kubeconfig file is either empty or malformed. Verify it's valid:
```bash
kubectl config view
```

### "No certificate-authority-data or file found for cluster X"
The cluster in your kubeconfig doesn't have a CA certificate configured. This is unusual and may indicate the cluster configuration is incomplete.

### Permission denied when creating PEM files
Ensure you have write access to the directory containing your kubeconfig:
```bash
ls -ld ~/.kube/
```

## Security considerations

- The script uses `base64 -d` to decode certificate data—this is safe as certificates are public information
- Certificate files are created with mode `644` (readable by all users on the system)
- The custom CA bundle is appended, not replacing the cluster's original CA, ensuring you maintain trust for the original certificate chain
