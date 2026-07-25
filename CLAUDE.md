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
