# charts/ — Helm chart convention

Each subdirectory is a Helm chart for one app deployed into a company cluster.

## Layout per chart

```
charts/<app>/
├── Chart.yaml
├── values.yaml          # Defaults + inline doc of every key
└── templates/
    ├── namespace.yaml
    ├── helmrelease.yaml  # HelmRelease wrapping the upstream chart
    └── ingress.yaml      # Ingress using ${company_domain} substitution
```

## Values contract

Every chart MUST accept these top-level values (used by the provisioning engine):

| Key | Type | Description |
|---|---|---|
| `companyId` | string | Company slug — used in resource names and labels |
| `domain` | string | Full company domain (e.g. `acme-demo.free-it-infra.com`) |
| `ingress.tlsSecret` | string | Name of the wildcard TLS secret in the app namespace |

Flux variable substitution (`${company_id}`, `${company_domain}`) is used in
GitOps manifests. The Helm values layer receives the same values at deploy time.

## Adding a new app chart

1. `mkdir charts/<app> && cd charts/<app>`
2. Copy `Chart.yaml` + `values.yaml` from an existing chart and adapt.
3. Add a `HelmRelease` in `gitops/clusters/company-template/apps/`.
4. Update the apps `kustomization.yaml` to include it.
