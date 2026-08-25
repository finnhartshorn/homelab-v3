# CLAUDE.md

## Renovate: grouping packages across datasources

When grouping a dependency across datasources with mismatched version
formats (e.g. a docker tag `v1.13.7` vs. a bare-versioned package `1.13.7`),
an `extractVersion` packageRule is used to strip the prefix so the two line
up for the grouped PR title. This has bitten us twice:

- Kubernetes group: `ghcr.io/siderolabs/kubelet` (docker, `v`-prefixed)
  grouped with `docker.io/alpine/k8s` (docker, bare).
- Talos group: `ghcr.io/siderolabs/installer` (docker, `v`-prefixed)
  grouped with `siderolabs/talos` (aqua, bare).

**The strip is global** — it applies to every file where Renovate updates
that depName's version, not just the tag itself. Any consumer file whose
regex/manager captures the version *with* the prefix inside the matched
group (e.g. the generic `# renovate: datasource=... depName=...` comment
convention used across `kubernetes/**/*.yaml`) will have the prefix
silently stripped on the next bump — even in files that require it
(talhelper's `talosVersion`, tuppr's CRD `version` fields both require the
`v`; only `kubernetesVersion` happens to be fine bare).

**Before adding an `extractVersion` packageRule**, grep the repo for every
place that depName's version is written, and for any file that needs the
prefix preserved, add a dedicated file-scoped `customManagers` regex entry
with the prefix as a *literal outside* the capture group (see the
`kubernetesupgrade.yaml` and `talosupgrade.yaml` managers in
`.github/renovate.json5` for the pattern), instead of relying on the
generic depName-comment manager.

## Renovate: non-standard field names are silently skipped

The default docker manager only matches an `image:` field. Any CRD or
manifest that stores an image under a differently-named field (e.g. CNPG's
`Cluster` resource uses `imageName:`, not `image:`) is invisible to
Renovate by default — it gets no PRs at all, with no error or warning.

This bit us with `kubernetes/apps/database/postgres/cluster/cluster.yaml`:
the `hypertable-maintenance-cronjob.yaml` and `logical-backup-cronjob.yaml`
in the same directory reference the same `ghcr.io/cloudnative-pg/postgresql`
image via `image:` and got bumped 18.4 → 18.6 automatically, while the
actual `Cluster.spec.imageName` sat untouched on 18.4 — silent version
drift between the running database and its own sidecar tooling.

**When adding a new manifest that pins an image via a non-`image:` field**,
add a dedicated `customManagers` regex entry for it (same `depNameTemplate`
as any sibling files referencing the same image, so Renovate groups them
into one PR — see the `cluster.yaml` manager in `.github/renovate.json5`
for the pattern) instead of assuming the default manager will find it.

## Talos: ALWAYS `--dry-run` before applying machine config

**Never run `talosctl apply-config` for real on a node before first running
the exact same command with `--dry-run` and reading the full diff.** No
exceptions, even for changes that look purely additive (a new patch file, a
`nodeLabels` addition, anything that seems unrelated to existing settings).

This repo's `talconfig.yaml` + `patches/` do **not** fully represent the
live machine config on every node. Settings have accumulated live over time
(sysctls, kernel modules, kubelet extraMounts, machine features) that were
never captured back into git. `talhelper genconfig` only knows what's in
git — anything live-but-undeclared gets silently *removed* the moment any
config gets applied for real, regardless of how small or targeted the
intended change is. `git diff` against the repo's own history cannot catch
this, because the drift isn't a git-tracked change — it's a gap between git
and reality that only shows up by diffing against the live node.

Concretely, before touching any node:

```
talosctl apply-config --dry-run --talosconfig=<path> --nodes=<ip> --file=<generated-node-file> --mode=auto
```

Read every line of the diff. Anything on a `-` line that isn't something
you intentionally meant to remove needs to be tracked down and added to a
patch file *before* applying for real — not fixed up after the fact. A
`--dry-run` diff against an already-modified node won't show you this
(it'll look clean, because the drift is already gone from that node) — the
only reliable check is running `--dry-run` against a node that hasn't been
touched yet, or against the specific node you're about to change, before
you change it.

This was learned the hard way: an apply without `--dry-run` first silently
dropped `vm.nr_hugepages`, `kernel.modules` (`nvme_tcp`, `vfio_pci`), a
`/var/lib/longhorn` kubelet extraMount, and several `machine.features`
flags from a live control-plane node — none of which were declared in git,
all of which only surfaced by diffing a *different*, still-untouched node
afterward.
