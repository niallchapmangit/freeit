# Provider Contract — substrate-<cloud> interface

Every `substrate-<cloud>` module MUST accept these inputs and emit this output.
Nothing outside `substrate-*` may import a cloud SDK or provider.

## Required inputs

| Variable        | Type           | Description |
|-----------------|----------------|-------------|
| `company_id`    | `string`       | Unique slug, used in resource names and tags. |
| `node_size`     | `string`       | Portable enum: `small` (1 vCPU / 1 GiB) · `medium` (2 vCPU / 4 GiB) · `large` (4 vCPU / 8 GiB). `medium` is the k3s floor. |
| `ssh_public_key`| `string`       | SSH public key material placed on the VM. |
| `ssh_cidrs`     | `list(string)` | CIDRs allowed on port 22. Never `["0.0.0.0/0"]`. |
| `api_cidrs`     | `list(string)` | CIDRs allowed on port 6443 (k3s API). Never `["0.0.0.0/0"]`. |
| `public_ports`  | `list(number)` | World-open ports (default `[80, 443]`). |
| `cloud_init`    | `string`       | Rendered cloud-init user-data (passed from `node-bootstrap`). |
| `region`        | `string`       | Cloud region. Must be EU for GDPR compliance. |
| `tags`          | `map(string)`  | Extra tags/labels to attach to all resources. |

## Required output — the `node` object

```hcl
output "node" {
  value = {
    public_ip  = string   # Stable public IP (EIP on AWS, reserved IP elsewhere)
    ssh_host   = string   # Same as public_ip unless provider uses a hostname
    ssh_user   = string   # Default SSH user (e.g. "ubuntu", "ec2-user")
    instance_id = string  # Provider-native resource ID (for audit / teardown)
    region      = string  # Actual region used
  }
}
```

## Rules

- Cloud SDK / provider resources appear **only** inside `substrate-*`.
- The portable layer (`node-bootstrap`, `stacks/company`, app Helm charts) consumes
  `node.*` and never references a cloud resource directly.
- Adding a new provider = one new `substrate-<cloud>/` directory + wire it into
  `stacks/company/main.tf` behind the existing `node` variable.
- `node_size` is mapped to provider-specific SKUs **inside** each substrate module.
  Never expose instance type strings outside substrate.
