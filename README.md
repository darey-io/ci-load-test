# CI Load Test

Load testing pipeline for k8s. Creates a cluster, deploys some apps, directs traffice at them and posts results on PRs.

## Quick Start

Just open a PR and it runs automatically. Or run locally:

```bash
./scripts/setup-cluster.sh
./scripts/deploy-apps.sh
./scripts/run-load-test.sh
```

## How It Works

**Setup**

Creates a KinD cluster (3 nodes), installs nginx-ingress, waits for it to be ready. Port maps localhost:80 into the cluster.

**Deploy**

Deploys two services (foo and bar) using http-echo. Each has 2 replicas. Ingress routes `foo.localhost` → foo service, `bar.localhost` → bar service.

The script waits for everything to be actually ready before continuing - deployments available, pods ready, ingress has LB assigned, and curls both endpoints to verify.

**Load Test**

Uses k6. Runs 3 stages:

- 30s ramp up to 20 users
- 60s sustained at 50 users
- 30s ramp down

Randomly hits both services. Fails if p95 > 500ms, p99 > 1000ms, or >10% failures.

**Results**

Parses k6 output, posts a markdown table as PR comment with metrics.

## Configuration

**More load?** Edit `scripts/run-load-test.sh`:

```javascript
stages: [
  { duration: "30s", target: 50 },
  { duration: "2m", target: 100 },
  { duration: "30s", target: 0 },
];
```

**More replicas?** Change in `k8s/foo-deployment.yaml` or `k8s/bar-deployment.yaml`:

```yaml
spec:
  replicas: 5
```

**Different thresholds?** Edit the k6 script:

```javascript
thresholds: {
  http_req_duration: ['p(95)<200', 'p(99)<500'],
  http_req_failed: ['rate<0.05'],
}
```

## Troubleshooting

**Pods stuck in Pending**

Cluster probably didn't start right or out of resources:

```bash
kubectl describe pod <pod-name>
kubectl get nodes
```

Check Docker is running and has enough memory.

**Ingress not working**

Check if controller picked it up:

```bash
kubectl describe ingress echo-ingress
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --tail=100
```

Test manually:

```bash
curl -H "Host: foo.localhost" http://localhost/
curl -H "Host: bar.localhost" http://localhost/
```

**Load test connection errors**

Apps probably not ready yet. Wait a bit or check pods:

```bash
kubectl get pods
kubectl logs <pod-name>
```

**Thresholds failing**

Your machine might be slow. Close other apps or lower thresholds:

```javascript
thresholds: {
  http_req_duration: ['p(95)<5000'],
}
```

**CI failing but local works**

Probably timeout or permissions. Check Actions logs. Increase timeouts in scripts or add `pull-requests: write` permission.

## Notes

Scripts use `set -euo pipefail` so they fail fast. `kubectl wait` commands have timeouts and error handlers that dump debug info before exiting.
