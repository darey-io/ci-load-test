#!/bin/bash
set -euo pipefail

echo "📊 Installing k6 load testing tool..."
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update
sudo apt-get install k6 -y

echo "🔥 Running load test..."

# Create k6 script
cat > /tmp/load-test.js << 'EOF'
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const errorRate = new Rate('errors');

export const options = {
  stages: [
    { duration: '30s', target: 20 },
    { duration: '1m', target: 50 },
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    errors: ['rate<0.1'],
  },
};

const hosts = ['foo.localhost', 'bar.localhost'];

export default function () {
  const host = hosts[Math.floor(Math.random() * hosts.length)];
  const expectedText = host.split('.')[0];
  
  const res = http.get('http://localhost/', {
    headers: { 'Host': host },
  });
  
  const success = check(res, {
    'status is 200': (r) => r.status === 200,
    'correct response': (r) => r.body.includes(expectedText),
  });
  
  errorRate.add(!success);
  sleep(0.1);
}
EOF

# Run k6 and capture output
k6 run /tmp/load-test.js --out json=/tmp/k6-results.json | tee /tmp/k6-output.txt

# Parse results and create markdown report
cat > /tmp/load-test-results.md << 'EOF'
## 🎯 Load Test Results

### Test Configuration
- **Duration**: 2 minutes (30s ramp-up → 1m sustained → 30s ramp-down)
- **Peak Virtual Users**: 50
- **Targets**: `foo.localhost` and `bar.localhost`
- **Traffic Pattern**: Randomized between both hosts

### Performance Metrics

EOF

# Extract key metrics from k6 output
echo '```' >> /tmp/load-test-results.md
grep -A 20 "checks\|http_req" /tmp/k6-output.txt | head -30 >> /tmp/load-test-results.md
echo '```' >> /tmp/load-test-results.md

cat >> /tmp/load-test-results.md << 'EOF'

### Summary
- ✅ Load test completed successfully
- 📈 Cluster handled randomized traffic to both services
- 🎯 Both foo and bar deployments responded correctly

---
*Generated automatically by CI Load Test workflow*
EOF

echo "✅ Load test completed and results saved"
cat /tmp/load-test-results.md
