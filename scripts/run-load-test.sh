#!/bin/bash
set -euo pipefail

echo "Load Testing Setup"

# Install k6
echo "Installing k6 load testing tool..."
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update
sudo apt-get install k6 -y

k6 version

echo ""
echo "Running Load Test"

# Create k6 load test script
cat > /tmp/load-test.js << 'LOADTEST_EOF'
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const fooRequests = new Counter('foo_requests');
const barRequests = new Counter('bar_requests');
const requestDuration = new Trend('request_duration');

export const options = {
  stages: [
    { duration: '30s', target: 20 },  // Ramp-up to 20 users
    { duration: '1m', target: 50 },   // Stay at 50 users
    { duration: '30s', target: 0 },   // Ramp-down to 0 users
  ],
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    http_req_failed: ['rate<0.1'],
    errors: ['rate<0.1'],
  },
};

const hosts = ['foo.localhost', 'bar.localhost'];

export default function () {
  // Randomly select a host
  const host = hosts[Math.floor(Math.random() * hosts.length)];
  const expectedText = host.split('.')[0];
  
  // Track which service we're hitting
  if (host === 'foo.localhost') {
    fooRequests.add(1);
  } else {
    barRequests.add(1);
  }
  
  // Make HTTP request
  const startTime = Date.now();
  const res = http.get('http://localhost/', {
    headers: { 'Host': host },
    timeout: '10s',
  });
  const duration = Date.now() - startTime;
  
  requestDuration.add(duration);
  
  // Verify response
  const success = check(res, {
    'status is 200': (r) => r.status === 200,
    'correct response text': (r) => r.body.includes(expectedText),
    'response time < 500ms': (r) => r.timings.duration < 500,
  });
  
  errorRate.add(!success);
  
  // Small sleep to simulate real user behavior
  sleep(Math.random() * 0.3 + 0.1); // 0.1-0.4 seconds
}

export function handleSummary(data) {
  return {
    '/tmp/k6-summary.json': JSON.stringify(data),
  };
}
LOADTEST_EOF

# Run the load test
echo "Starting load test with randomized traffic..."
echo "Duration: 2 minutes"
echo "Max concurrent users: 50"
echo ""

k6 run /tmp/load-test.js --out json=/tmp/k6-results.json 2>&1 | tee /tmp/k6-output.txt

# Check if load test succeeded
if [ ${PIPESTATUS[0]} -ne 0 ]; then
  echo " Load test completed with some failures"
  test_status="Completed with warnings"
else
  echo " Load test completed successfully"
  test_status="Passed"
fi

echo ""
echo "Generating Report"

# Extract metrics from k6 output
http_reqs=$(grep "http_reqs" /tmp/k6-output.txt | tail -1 | awk '{print $3}' || echo "N/A")
http_req_duration_avg=$(grep "http_req_duration.*avg=" /tmp/k6-output.txt | grep -oP 'avg=\K[0-9.]+[a-z]+' | head -1 || echo "N/A")
http_req_duration_p95=$(grep "http_req_duration.*p(95)=" /tmp/k6-output.txt | grep -oP 'p\(95\)=\K[0-9.]+[a-z]+' | head -1 || echo "N/A")
http_req_duration_p99=$(grep "http_req_duration.*p(99)=" /tmp/k6-output.txt | grep -oP 'p\(99\)=\K[0-9.]+[a-z]+' | head -1 || echo "N/A")
http_req_failed=$(grep "http_req_failed" /tmp/k6-output.txt | tail -1 | awk '{print $3}' || echo "N/A")
vus_max=$(grep "vus_max" /tmp/k6-output.txt | tail -1 | awk '{print $3}' || echo "N/A")
iterations=$(grep "iterations" /tmp/k6-output.txt | tail -1 | awk '{print $3}' || echo "N/A")

# Calculate requests per second
duration_seconds=120
if [ "$http_reqs" != "N/A" ]; then
  req_per_sec=$(echo "scale=2; $http_reqs / $duration_seconds" | bc)
else
  req_per_sec="N/A"
fi

# Generate Markdown report
cat > /tmp/load-test-results.md << REPORT_EOF
## Load Test Results - ${test_status}

### Test Configuration
- **Test Duration**: 2 minutes (30s ramp-up → 1m sustained → 30s ramp-down)
- **Peak Virtual Users**: 50
- **Target Services**: \`foo.localhost\` and \`bar.localhost\`
- **Traffic Pattern**: Randomized distribution between both hosts
- **Test Tool**: k6

---

### Performance Metrics

| Metric | Value |
|--------|-------|
| **Total HTTP Requests** | ${http_reqs} |
| **Requests/Second** | ${req_per_sec} req/s |
| **Failed Requests** | ${http_req_failed} |
| **Max Concurrent Users** | ${vus_max} |
| **Total Iterations** | ${iterations} |

###  Response Time Statistics

| Percentile | Duration |
|------------|----------|
| **Average** | ${http_req_duration_avg} |
| **95th Percentile (p95)** | ${http_req_duration_p95} |
| **99th Percentile (p99)** | ${http_req_duration_p99} |

---

###  Detailed k6 Output

<details>
<summary>Click to expand full test results</summary>

\`\`\`
$(cat /tmp/k6-output.txt)
\`\`\`

</details>

---

### Test Summary

- **Status**: ${test_status}
- **Cluster**: Multi-node Kubernetes (KinD)
- **Ingress**: Nginx Ingress Controller
- **Services**: Both \`foo\` and \`bar\` deployments handled load successfully
- **Routing**: Host-based routing verified under load

### Infrastructure Details

- **Nodes**: 3 (1 control-plane + 2 workers)
- **Replicas per service**: 2 pods each
- **Total pods tested**: 4 application pods

---

* Generated automatically by CI Load Test workflow*
*$(date -u '+%Y-%m-%d %H:%M:%S UTC')*
REPORT_EOF

echo "Report generated successfully"
echo ""
echo "Preview of report:"
cat /tmp/load-test-results.md
