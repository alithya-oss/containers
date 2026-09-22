# CI scripts

## `list-changed-images.js`

Detects which image workspaces under `images/<name>/` changed relative to a base
ref and emits a JSON matrix consumed by the workflows in `.github/workflows/`.
Inspired by
[backstage/community-plugins' `list-workspaces-with-changes.js`](https://github.com/backstage/community-plugins/blob/main/scripts/ci/list-workspaces-with-changes.js),
scoped to this container monorepo.

### Behaviour

- A **buildable image** is a directory `images/<name>/` containing a `Dockerfile`.
- A change under `images/<name>/**` selects that image.
- A change to a **global** path — `.github/workflows/**`, `scripts/ci/**`,
  `.hadolint.yaml`, `Taskfile.yaml` — selects **all** buildable images.
- A change under a declared shared base dir (`BASE_DIRS` in the script) fans out
  to its dependents. Empty today because no image builds `FROM images/base`;
  adding a real shared base only needs an entry there.
- An unknown/zero base ref (first push or force-push) selects **all** images.

### Outputs

Written to `$GITHUB_OUTPUT` (and echoed to stdout):

- `images` — JSON array, e.g. `["awstools","kirocrew"]`
- `has_changes` — `"true"` | `"false"`

### Usage

```bash
BASE_REF=origin/main node scripts/ci/list-changed-images.js
```

The workflows run a `detect` job that calls this script, then a dynamic
`strategy.matrix.image: ${{ fromJson(needs.detect.outputs.images) }}` build job,
and a final `result` aggregator job used as the single required status check
(individual matrix legs cannot be required because their names vary).
