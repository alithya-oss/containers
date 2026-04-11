## Using in Argo Workflows

### Prerequisites

- Argo Workflows installed in your cluster
- Access to the container registry where the azcopy image is stored

### Example Workflow

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: azcopy-
spec:
  entrypoint: azcopy-copy
  templates:
    - name: azcopy-copy
      container:
        image: ghcr.io/<owner>/azcopy:latest
        command: [azcopy]
        args:
          - "copy"
          - "https://<storage-account>.blob.core.windows.net/<container>/<path>"
          - "/data"
          - "--include-pattern"
          - "*.csv"
        env:
          - name: AZCOPY_AUTO_LOGIN_TYPE
            value: "AZCLI"
        volumeMounts:
          - name: data
            mountPath: /data
      volumes:
        - name: data
          emptyDir: {}

    # Example with authentication via environment variables
    - name: azcopy-copy-with-auth
      container:
        image: ghcr.io/<owner>/azcopy:latest
        command: [azcopy]
        args:
          - "copy"
          - "https://<source-account>.blob.core.windows.net/<source-container>"
          - "https://<dest-account>.blob.core.windows.net/<dest-container>"
          - "--recursive"
        env:
          - name: AZCOPY_SPA_CLIENT_ID
            valueFrom:
              secretKeyRef:
                name: azcopy-secrets
                key: client-id
          - name: AZCOPY_SPA_TENANT_ID
            valueFrom:
              secretKeyRef:
                name: azcopy-secrets
                key: tenant-id
          - name: AZCOPY_SPA_CLIENT_SECRET
            valueFrom:
              secretKeyRef:
                name: azcopy-secrets
                key: client-secret
```

### Example: Copy from Azure Blob to PVC

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: azcopy-blob-to-pvc-
spec:
  entrypoint: main
  templates:
    - name: main
      steps:
        - - name: download-from-azure
            template: azcopy-download

    - name: azcopy-download
      container:
        image: ghcr.io/<owner>/azcopy:latest
        command: [azcopy]
        args:
          - "copy"
          - "https://mystorageaccount.blob.core.windows.net/mycontainer/data/*"
          - "/data"
          - "--recursive=true"
        env:
          - name: AZCOPY_AUTO_LOGIN_TYPE
            value: "AZCLI"
        volumeMounts:
          - name: data-volume
            mountPath: /data
      volumes:
        - name: data-volume
          persistentVolumeClaim:
            claimName: my-data-claim
```

### Example: Copy Between Storage Accounts

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: azcopy-sync-
spec:
  entrypoint: main
  templates:
    - name: main
      steps:
        - - name: sync-storage-accounts
            template: azcopy-sync

    - name: azcopy-sync
      container:
        image: ghcr.io/<owner>/azcopy:latest
        command: [azcopy]
        args:
          - "sync"
          - "https://sourceaccount.blob.core.windows.net/sourcecontainer"
          - "https://destaccount.blob.core.windows.net/destcontainer"
          - "--recursive=true"
        env:
          - name: AZCOPY_SPA_CLIENT_ID
            valueFrom:
              secretKeyRef:
                name: azcopy-secrets
                key: client-id
          - name: AZCOPY_SPA_CLIENT_SECRET
            valueFrom:
              secretKeyRef:
                name: azcopy-secrets
                key: client-secret
          - name: AZCOPY_SPA_TENANT_ID
            valueFrom:
              secretKeyRef:
                name: azcopy-secrets
                key: tenant-id
```

