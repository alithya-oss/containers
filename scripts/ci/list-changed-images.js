#!/usr/bin/env node
// =============================================================================
// list-changed-images.js
// -----------------------------------------------------------------------------
// Detects which image "workspaces" under images/<name>/ changed relative to a
// base ref and emits a JSON matrix for the CI workflows to consume. Inspired by
// backstage/community-plugins' scripts/ci/list-workspaces-with-changes.js, but
// scoped to this container monorepo.
//
// A "buildable image" is a directory images/<name>/ that contains a Dockerfile.
//
// Rules:
//   * Change under images/<name>/**            -> that image.
//   * Change to a GLOBAL path (CI workflows,
//     scripts/ci, this script, .hadolint.yaml,
//     Taskfile)                                -> ALL buildable images.
//   * Change under a declared shared BASE dir
//     (see BASE_DIRS) that other images build
//     FROM                                     -> fan out to its dependents
//     (today no image builds FROM images/base, so this is future-proofing).
//
// Outputs (written to $GITHUB_OUTPUT when present, else stdout):
//   images       JSON array of image names, e.g. ["awstools","kirocrew"]
//   has_changes  "true" | "false"
//
// Usage:
//   BASE_REF=origin/main node scripts/ci/list-changed-images.js
// =============================================================================
'use strict';

const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const IMAGES_DIR = 'images';

// Paths that affect every image: a change here rebuilds the whole catalog.
const GLOBAL_PATTERNS = [
  /^\.github\/workflows\//,
  /^scripts\/ci\//,
  /^\.hadolint\.ya?ml$/,
  /^Taskfile\.ya?ml$/,
];

// Shared base directories that other images may build FROM. Map a base dir to
// the list of dependent image names to rebuild when it changes. Empty today
// because no image currently builds FROM images/base, but wired so adding a
// real shared base only needs an entry here.
const BASE_DIRS = {
  // 'images/base': ['awstools', 'azuretools', 'kirocrew'],
};

function run(cmd, args) {
  return execFileSync(cmd, args, { encoding: 'utf8' }).trim();
}

// List directories under images/ that contain a Dockerfile (buildable).
function buildableImages() {
  const root = path.join(process.cwd(), IMAGES_DIR);
  if (!fs.existsSync(root)) return [];
  return fs
    .readdirSync(root, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => d.name)
    .filter((name) => fs.existsSync(path.join(root, name, 'Dockerfile')))
    .sort();
}

function changedFiles(baseRef) {
  const ZERO = '0000000000000000000000000000000000000000';
  // Unknown base (first push to a branch, or a force-push): we cannot compute a
  // reliable diff, so signal "everything" by returning null.
  if (!baseRef || baseRef === ZERO) return null;

  // Verify the base ref actually resolves; if not, fall back to "everything".
  try {
    run('git', ['rev-parse', '--verify', `${baseRef}^{commit}`]);
  } catch {
    return null;
  }

  // Use merge-base ("...") so we only see what THIS branch changed, not commits
  // that landed on the base since it forked.
  let diffBase = baseRef;
  try {
    diffBase = run('git', ['merge-base', baseRef, 'HEAD']);
  } catch {
    // No common ancestor available (shallow clone): fall back to the base ref.
  }
  const out = run('git', ['diff', '--name-only', `${diffBase}`, 'HEAD']);
  return out ? out.split('\n').filter(Boolean) : [];
}

function main() {
  const baseRef = process.env.BASE_REF || 'origin/main';
  const all = buildableImages();
  const files = changedFiles(baseRef);

  // null => base unknown (first push / force-push): build everything.
  if (files === null) {
    const output = { images: all, has_changes: all.length > 0 ? 'true' : 'false' };
    emit(output);
    return;
  }

  const isGlobal = files.some((f) => GLOBAL_PATTERNS.some((re) => re.test(f)));

  let selected;
  if (isGlobal) {
    selected = all.slice();
  } else {
    const set = new Set();
    for (const f of files) {
      const m = f.match(/^images\/([^/]+)\//);
      if (m && all.includes(m[1])) set.add(m[1]);
      for (const [baseDir, dependents] of Object.entries(BASE_DIRS)) {
        if (f.startsWith(`${baseDir}/`)) dependents.forEach((d) => set.add(d));
      }
    }
    selected = [...set].sort();
  }

  emit({
    images: selected,
    has_changes: selected.length > 0 ? 'true' : 'false',
  });
}

function emit(output) {
  const gha = process.env.GITHUB_OUTPUT;
  const lines = [
    `images=${JSON.stringify(output.images)}`,
    `has_changes=${output.has_changes}`,
  ];
  if (gha) {
    fs.appendFileSync(gha, `${lines.join('\n')}\n`);
  }
  // Always echo for logs / local runs.
  console.log(lines.join('\n'));
}

main();
