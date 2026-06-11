# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**kube-cert-bundler** is a single-purpose Bash utility that bundles custom CA certificates with Kubernetes cluster certificates in kubeconfig files. This is essential for organizations using corporate proxies, internal CAs, or MITM certificate inspection.

The project consists of:
- `bundle-kube-certs.sh`: Single executable script (~120 lines) that performs the bundling operation
- `README.md`: User documentation
- `CLAUDE.md`: This file

## Architecture & Design

The script follows a straightforward imperative design:

1. **Validation phase**: Checks that bundle file and kubeconfig exist
2. **Discovery phase**: Uses `kubectl config get-clusters` to list all clusters
3. **Processing loop**: For each cluster:
   - Extracts CA certificate (handles both inline `certificate-authority-data` and file-referenced `certificate-authority`)
   - Saves to a new `.pem` file alongside the kubeconfig
   - Appends the custom CA bundle
   - Updates kubeconfig to reference the new file
   - Removes inline certificate data

**Key design decisions**:
- Uses `kubectl config` commands rather than direct kubeconfig parsing—maintains compatibility with kubectl's behavior
- Idempotent: detects already-processed clusters by checking for `.pem` file existence + absence of inline data
- Handles both inline and file-based certificates to cover various kubeconfig configurations
- Base64 decoding happens locally, not via `--flatten` (which can fail with file access errors)

## Testing & Validation

This is a utility script without automated tests. To verify changes:

1. **Manual testing required**: Create a test kubeconfig with one or more clusters
2. **Test with sample certificates**: Use dummy PEM files for the bundle
3. **Verify output**: Check that:
   - `.pem` files are created in the correct directory
   - kubeconfig is updated to reference the files
   - Certificate bundle is properly appended
   - Running again skips already-processed clusters (idempotency)

Example test setup:
```bash
# Create test certificates
openssl genrsa -out /tmp/test-ca.key 2048
openssl req -new -x509 -days 365 -key /tmp/test-ca.key -out /tmp/test-ca.pem

# Create test kubeconfig (or use an existing one)
export KUBECONFIG=/tmp/test-kubeconfig

# Run the script
./bundle-kube-certs.sh /tmp/test-ca.pem
```

## Development Notes

- The script is self-contained and has no external dependencies beyond `kubectl` and standard Unix tools
- Error handling uses `set -e` to exit on any command failure
- Output uses Unicode symbols (✓, ⊘, ℹ, ⚠) for clarity—ensure terminal compatibility
- The `--help` output is embedded in the script and duplicated in README.md—keep them in sync

## Common Tasks

**Run the script**:
```bash
./bundle-kube-certs.sh /path/to/bundle.pem [/path/to/kubeconfig]
```

**Test with custom kubeconfig**:
```bash
./bundle-kube-certs.sh /path/to/bundle.pem /custom/kubeconfig/path
```

**Display help**:
```bash
./bundle-kube-certs.sh --help
```

**Check the generated files**:
```bash
ls -la ~/.kube/*-ca.pem
```
