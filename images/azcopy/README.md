# Azcopy Container Image

This container image runs [azcopy](https://github.com/Azure/azure-storage-azcopy), a command-line utility for copying data to/from Microsoft Azure Blob Storage and Azure File Storage.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `AZCOPY_AUTO_LOGIN_TYPE` | Authentication type (e.g., `AZCLI`, `MANAGED_IDENTITY`, `OAUTH`) |
| `AZCOPY_SPA_CLIENT_ID` | Service Principal client ID |
| `AZCOPY_SPA_CLIENT_SECRET` | Service Principal client secret |
| `AZCOPY_SPA_TENANT_ID` | Service Principal tenant ID |
| `AZCOPY_ACCOUNT_KEY` | Storage account key for authentication |
| `AZCOPY_LOG_LOCATION` | Directory for azcopy logs (default: user's temp directory) |
| `AZCOPY_CONCURRENCY` | Number of concurrent operations |
| `AZCOPY_BUFFER_GB` | Memory buffer size in GB |



## Building the Image

### Prerequisites

- Docker with Buildx plugin
- Access to build the image (local or CI/CD)

### Build Locally

```bash
cd images/azcopy
docker buildx build --platform linux/amd64 -t azcopy:latest .
```

### Build with Custom Version

The image supports configurable versions via build arguments:

#### Build Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `AZCOPY_VERSION` | `10.32.3` | Version of azcopy to build |
| `GO_VERSION` | `1.26` | Go version used for building azcopy |
| `ALPINE_VERSION` | `3.23` | Alpine Linux base version |
| `TARGETARCH` | `amd64` | Target CPU architecture |

```bash
docker buildx build \
  --platform linux/amd64 \
  --build-arg AZCOPY_VERSION=10.32.3 \
  --build-arg GO_VERSION=1.26 \
  --build-arg ALPINE_VERSION=3.23 \
  -t oci.local/azcopy:10.32.3 \
  .
```

## Authentication Options

The azcopy image supports multiple authentication methods:

### 1. Azure CLI (AZCLI)
```bash
AZCOPY_AUTO_LOGIN_TYPE=AZCLI
```
Requires `az login` to be executed in the container (not suitable for non-interactive workflows).

### 2. Service Principal (SPA)
```bash
AZCOPY_SPA_CLIENT_ID=<client-id>
AZCOPY_SPA_CLIENT_SECRET=<client-secret>
AZCOPY_SPA_TENANT_ID=<tenant-id>
```

### 3. Shared Access Signature (SAS)
Append a SAS token to the URL:
```bash
https://account.blob.core.windows.net/container/blob?sas-token
```

### 4. Account Key
```bash
AZCOPY_ACCOUNT_KEY=<account-key>
```

## Available Commands

The container includes the full azcopy CLI. Common commands:

- `azcopy copy <source> <destination>` - Copy data
- `azcopy sync <source> <destination>` - Sync data (only copies changed/deleted files)
- `azcopy list <container-url>` - List blobs in a container
- `azcopy login` - Authenticate to Azure
- `azcopy logout` - Logout from Azure

Run `azcopy --help` for a complete list of commands and options.
