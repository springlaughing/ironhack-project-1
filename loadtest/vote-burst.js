// Load test 1: a burst of votes against the Vote server.
// Default: 400 votes per second for 5 seconds = 2,000 votes.
import http from 'k6/http';
import { check } from 'k6';

const RATE = Number(__ENV.RATE || 400);
const DURATION = __ENV.DURATION || '5s';
const TARGET = __ENV.TARGET || 'http://vote/';   // where to send votes; default = local compose

export const options = {
  scenarios: {
    burst: {
      executor: 'constant-arrival-rate',  // a fixed number of new votes per second
      rate: RATE,
      timeUnit: '1s',
      duration: DURATION,
      preAllocatedVUs: 50,
      maxVUs: 300,
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],     // fewer than 1% errors
    http_req_duration: ['p(95)<500'],   // 95% of votes answered within 0.5 s
  },
};

export default function () {
  // A unique voter per request, so every vote becomes its own row
  const voter = `k6-${__VU}-${__ITER}`;
  const res = http.post(TARGET, { vote: Math.random() < 0.5 ? 'a' : 'b' }, {    headers: { Cookie: `voter_id=${voter}` },
  });
  check(res, { 'vote accepted (200)': (r) => r.status === 200 });
}
