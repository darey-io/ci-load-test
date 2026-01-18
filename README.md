# CI Load Test

Automated load testing pipeline for Kubernetes. Spins up a local cluster, deploys some test apps, hammers them with traffic, and reports back on a PR.

When you open a PR, GitHub Actions automatically creates a 3-node Kubernetes cluster using KinD, deploys two simple HTTP services that respond with different messages based on the hostname, sets up ingress routing to handle the traffic distribution, runs a 2-minute load test that randomly hits both services, and posts detailed performance metrics as a comment directly on your PR.

## Quick Start
```bash
# Clone and create a PR 
git checkout -b test
git push origin test
# Open PR on GitHub
```

Want to test locally first? Run the scripts in order:
```bash
./scripts/setup-cluster.sh    # Takes about 90 seconds
./scripts/deploy-apps.sh      # Takes about 60 seconds
./scripts/run-load-test.sh    # Takes about 2 minutes
```

Each script is designed to fail fast if something goes wrong, so you'll know immediately if there's an issue rather than waiting through the whole pipeline.

## Project Structure
```
├── .github/workflows/
│   └── load-test.yml          # CI workflow - orchestrates everything
├── k8s/
│   ├── foo-deployment.yaml    # First test service (responds with "foo")
│   ├── bar-deployment.yaml    # Second test service (responds with "bar")
│   └── ingress.yaml           # Routing config for hostname-based routing
├── scripts/
│   ├── setup-cluster.sh       # Creates KinD cluster + installs ingress controller
│   ├── deploy-apps.sh         # Deploys apps + validates they're working
│   └── run-load-test.sh       # Runs k6 load test + generates report
└── README.md
```

## How It Works

**Cluster Setup (~90 seconds)** 

The `setup-cluster.sh` script creates a local Kubernetes cluster using KinD (Kubernetes in Docker) with 1 control-plane node and 2 worker nodes. We're using KinD specifically because it supports multi-node clusters out of the box and runs fast in CI environments. Minikube would require extra config for multi-node, and k3s felt like overkill for this use case.

The script also installs the nginx-ingress controller and waits for it to be fully ready before proceeding. This is important because the ingress controller needs to be running before we can configure any routing rules. We use `kubectl wait --for=condition=ready` to ensure the controller pods are actually healthy, not just "Running" (pods can be in Running state but still failing their readiness checks).

The cluster is configured with port mappings so that traffic to `localhost:80` on your machine gets routed into the cluster. This lets us test the ingress routing without needing a real domain name or external load balancer.

**App Deployment (~60 seconds)** 

The `deploy-apps.sh` script deploys two identical services using hashicorp/http-echo, which is a super simple HTTP server that just echoes back whatever text you configure it with. One service responds with "foo" and the other with "bar". This makes it really easy to verify that routing is working correctly - if you hit `foo.localhost` and get back "bar", you know something's wrong.

Each deployment runs 2 replicas (pods) for basic load distribution across the worker nodes. The ingress configuration uses hostname-based routing:
- Requests to `foo.localhost` → routed to the foo service
- Requests to `bar.localhost` → routed to the bar service

The script doesn't just fire off `kubectl apply` and hope for the best. It actively waits and validates at each step:

1. Waits for deployments to be available (`kubectl wait --for=condition=available`)
2. Waits for all pods to pass their readiness checks (`kubectl wait --for=condition=ready`)
3. Waits for the ingress to have a load balancer assigned (`kubectl wait --for=jsonpath='{.status.loadBalancer.ingress}'`)
4. Actually curls both endpoints to verify they return the correct responses

This progressive validation catches issues early. For example, if a pod image can't be pulled, or if the ingress is misconfigured, we find out immediately with detailed error output instead of discovering it 5 minutes later when the load test fails.

**Load Testing (~2 minutes)** 

The `run-load-test.sh` script uses k6 to generate realistic traffic patterns. k6 was chosen over alternatives like JMeter (too heavy, XML configs are painful) or Locust (slower, less detailed metrics) because it's lightweight, uses JavaScript for config, and provides excellent built-in metrics.

The test runs in three stages:
- 30 seconds ramping up from 0 to 20 concurrent users
- 60 seconds sustained load at 50 concurrent users
- 30 seconds ramping down to 0

During the test, each virtual user randomly picks either `foo.localhost` or `bar.localhost` and makes an HTTP request with the appropriate Host header. This randomization ensures both services get roughly equal traffic, which is more realistic than hitting them sequentially.

The test validates not just that requests succeed, but that they return the *correct* response. If routing is broken and foo requests are going to the bar service, the test will catch it.

Performance thresholds are configured to fail the test if:
- 95th percentile latency exceeds 500ms
- 99th percentile latency exceeds 1000ms  
- More than 10% of requests fail

These are reasonable defaults but you can adjust them based on your requirements.

**Results** 

After the load test completes, the script parses the k6 output to extract key metrics like total requests, requests per second, failure rate, and latency percentiles (average, p95, p99). It formats these into a markdown table and posts it as a comment on the PR.

The PR comment includes:
- High-level summary (pass/fail status, total requests, throughput)
- Response time statistics broken down by percentile
- Full k6 output in a collapsible `<details>` section for debugging

Results are also uploaded as workflow artifacts and kept for 30 days, so you can download the raw JSON output if you need to do deeper analysis.

## Configuration

**Adjust load test intensity** by editing the stages in `scripts/run-load-test.sh`. The current config is pretty light - if you want to stress test harder, increase the target users:
```javascript
stages: [
  { duration: '30s', target: 50 },    // ramp-up to 50 instead of 20
  { duration: '2m', target: 100 },    // sustained load at 100 users for 2 minutes
  { duration: '30s', target: 0 },     // ramp-down
]
```

**Scale deployments** by changing replicas in `k8s/foo-deployment.yaml` or `k8s/bar-deployment.yaml`. More replicas means better load distribution but also slower deployment times:
```yaml
spec:
  replicas: 5  # run 5 pods instead of 2
```

**Modify performance thresholds** in the k6 script. If your services are naturally slower or you want stricter requirements:
```javascript
thresholds: {
  http_req_duration: ['p(95)<200', 'p(99)<500'],  // stricter latency requirements
  http_req_failed: ['rate<0.05'],                  // only allow 5% failures
}
```

**Change resource limits** in the deployment YAMLs if your apps need more memory or CPU:
```yaml
resources:
  requests:
    memory: "128Mi"
    cpu: "200m"
  limits:
    memory: "256Mi"
    cpu: "500m"
```

## Tech Choices

**Why KinD?** 

Need multi-node support for realistic testing. Minikube is single-node by default (you can enable multi-node but it's awkward), k3s is solid but overkill for a CI test environment, and managed Kubernetes services like GKE/EKS would be too slow and expensive for every PR. KinD is purpose-built for testing Kubernetes itself, so it's optimized for exactly this use case - fast startup, multi-node support, runs anywhere Docker runs.

**Why k6?** 

JMeter is a memory hog (runs on JVM) and uses XML configs which are a pain to work with. Locust is decent but slower and doesn't have as detailed metrics out of the box. Artillery is simpler but less mature and the metrics aren't as good. k6 is written in Go so it's fast and lightweight, uses JavaScript for scripting (way better DX than XML), and provides excellent percentile metrics without needing to pipe to external tools.

**Why Nginx Ingress?** 

Industry standard - most production Kubernetes clusters use it. Traefik is fine and has some nice auto-discovery features, but nginx has better documentation and KinD provides official manifests for it. HAProxy Ingress is more niche. Istio/Envoy would be massive overkill for simple hostname routing.

**Why GitHub Actions?** 

We're already on GitHub, so it's the path of least resistance. Free for public repos, decent free tier for private repos, and the YAML config is straightforward. Could export to Jenkins or GitLab CI if needed, but Actions has everything we need and the `github-script` action makes posting PR comments trivial (no need to mess with curl and auth tokens).

## Troubleshooting

**Pods stuck in Pending state**

Usually means the cluster didn't start properly or ran out of resources. Check what's going on:
```bash
kubectl describe pod <pod-name>  # Look for events at the bottom
kubectl get nodes                 # Verify all nodes are Ready
```

Common causes: Docker not running, insufficient memory allocated to Docker Desktop, or the KinD cluster creation failed partway through.

**Ingress not routing traffic**

The deployment script waits for the ingress to have a load balancer assigned using `kubectl wait --for=jsonpath='{.status.loadBalancer.ingress}'`. If this times out (3 minutes), it means the ingress controller didn't pick up the ingress resource. Check the controller logs:
```bash
kubectl describe ingress echo-ingress  # See if there are any warnings
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --tail=100
```

You can also test the routing manually to isolate the issue:
```bash
curl -H "Host: foo.localhost" http://localhost/  # Should return "foo"
curl -H "Host: bar.localhost" http://localhost/  # Should return "bar"
```

If manual curls work but the automated test fails, the issue is in the test script. If manual curls don't work, the problem is with the ingress or service configuration.

**Load test failing with connection errors**

This usually means the apps aren't actually ready when the test starts. The `deploy-apps.sh` script should catch this, but if you're running the load test manually without waiting, you'll hit this. Give it another minute or check if the pods are actually healthy:
```bash
kubectl get pods                    # All should show 2/2 READY
kubectl logs <pod-name>             # Check for errors
```

**Load test failing threshold checks**

If requests are succeeding but latencies are higher than expected, check what else is running on your machine. KinD runs inside Docker containers, so if your machine is under heavy load, you'll see degraded performance. Close other apps and try again.

You can also lower the thresholds if you're just testing the pipeline, not actual performance:
```javascript
thresholds: {
  http_req_duration: ['p(95)<5000'],  // super lenient
}
```

**GitHub Actions workflow failing but local scripts work**

Could be a timeout issue (CI runners can be slower than your local machine) or a permissions issue with posting PR comments. Check the Actions logs for the specific error. If it's a timeout, you might need to increase the `--timeout` values in the scripts. If it's a permissions error, make sure the workflow has `pull-requests: write` permission.

## Notes

The whole pipeline takes about 5-6 minutes end-to-end on GitHub's standard runners. If you're running locally on a beefier machine, it'll be faster.

Results get uploaded as workflow artifacts and are available for 30 days. If you need them longer, you'd have to set up external storage (S3, GCS, etc).

All scripts use `set -euo pipefail` which is just defensive bash scripting - fail fast if any command errors, treat undefined variables as errors, and fail if any command in a pipeline fails (not just the last one). Makes debugging way easier than having scripts continue after errors and produce cryptic failures later.

The `kubectl wait` commands with timeouts and error handlers are there to catch problems immediately. Without them, the scripts would just hang or fail mysteriously later. The `|| { ... }` blocks run debugging commands (describe, logs, etc) before exiting so you have context about what went wrong.

**Possible future improvements:**

- Add Prometheus/Grafana to capture CPU/memory metrics during the load test (would make the report more comprehensive)
- Convert to Helm charts if the number of services grows beyond 2-3 (raw YAML gets tedious)
- Make test duration and intensity configurable via workflow dispatch inputs
- Store results in a database and show trends across PRs (which commits improved performance)
- Cache Docker images to speed up cluster startup (KinD has to pull images on every run)
- Add network policies to test behavior under constrained conditions
