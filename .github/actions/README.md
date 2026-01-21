# Reusable Actions

This directory contains reusable composite actions that demonstrate code reuse in GitHub Actions workflows.

## Available Actions

### `setup-kind`
Sets up a KinD (Kubernetes in Docker) cluster with nginx ingress controller.

**Inputs:**
- `cluster-name` - Name of the cluster (default: `load-test-cluster`)
- `kind-version` - KinD version (default: `v0.20.0`)
- `ingress-version` - Nginx ingress version (default: `controller-v1.9.4`)
- `wait-timeout` - Timeout for readiness checks (default: `300s`)

**Usage:**
```yaml
- uses: ./.github/actions/setup-kind
  with:
    cluster-name: 'my-cluster'
```

### `setup-k6`
Installs k6 load testing tool.

**Inputs:**
- `k6-version` - k6 version channel (default: `stable`)

**Usage:**
```yaml
- uses: ./.github/actions/setup-k6
```

### `wait-for-deployment`
Waits for a Kubernetes deployment and optionally its pods to be ready.

**Inputs:**
- `deployment-name` - Name of the deployment (required)
- `namespace` - Namespace (default: `default`)
- `timeout` - Timeout in seconds (default: `180s`)
- `check-pods` - Also wait for pods (default: `true`)

**Usage:**
```yaml
- uses: ./.github/actions/wait-for-deployment
  with:
    deployment-name: 'my-app'
    timeout: '300s'
```

### `post-pr-comment`
Posts a comment to a PR using github-script.

**Inputs:**
- `comment-file` - Path to file containing comment markdown (required)

**Usage:**
```yaml
- uses: ./.github/actions/post-pr-comment
  with:
    comment-file: '/tmp/results.md'
```

## Benefits of Modularization

1. **Code Reuse** - Actions can be used across multiple workflows
2. **Maintainability** - Update logic in one place, affects all workflows
3. **Testability** - Test actions independently
4. **Consistency** - Same behavior across all workflows using the action
5. **Documentation** - Self-documenting with inputs/outputs

## Example: Reusable Workflow

See `load-test-reusable.yml` for an example of calling a reusable workflow that uses these actions.

