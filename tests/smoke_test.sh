#!/usr/bin/env bash
# Round-trips a log through Loki to prove the ingester + querier + filesystem
# storage all work end-to-end. Strategy:
#
#   1. `kubectl run` a curl pod inside the cluster (avoids needing an
#      external port-forward, which is racy with itest's lifecycle).
#   2. From that pod, POST a synthetic log line to Loki's push API.
#   3. From the same pod, GET it back via the query API and grep for the
#      payload string.
#
# Loki's `auth_enabled: false` (config/loki-values.yaml) means no
# X-Scope-OrgID header is required.
set -euo pipefail

CLUSTER_NAME="cluster"
env_file="$TEST_TMPDIR/${CLUSTER_NAME}.env"
[[ -f "$env_file" ]] || { echo "missing kind env file" >&2; exit 1; }
# shellcheck disable=SC1090
source "$env_file"

KCTL=("$KUBECTL" --kubeconfig="$KUBECONFIG")

LOKI_HOST="loki.loki.svc.cluster.local:3100"
PAYLOAD="rules_loki-smoke-$(date +%s)-$RANDOM"
NS="${LOKI_SMOKE_NS:-default}"

echo "smoke_test: launching curl pod"
"${KCTL[@]}" -n "$NS" run loki-curl --restart=Never --image=curlimages/curl:8.10.1 \
    --command -- sleep 600
trap '"${KCTL[@]}" -n "$NS" delete pod loki-curl --ignore-not-found --wait=false >/dev/null 2>&1 || true' EXIT

"${KCTL[@]}" -n "$NS" wait pod/loki-curl --for=condition=Ready --timeout=60s

# Loki rejects pushes whose timestamps are far in the past or future.
# Now (in nanoseconds) is the safe choice.
NS_NOW=$(date +%s%N)

PUSH_BODY=$(cat <<EOF
{"streams":[{"stream":{"app":"rules_loki_smoke"},"values":[["${NS_NOW}","${PAYLOAD}"]]}]}
EOF
)

echo "smoke_test: pushing synthetic log to /loki/api/v1/push (payload=$PAYLOAD)"
push_status=$("${KCTL[@]}" -n "$NS" exec loki-curl -- \
    curl -s -o /dev/null -w "%{http_code}" \
    -X POST -H "Content-Type: application/json" \
    --data-binary "$PUSH_BODY" \
    "http://${LOKI_HOST}/loki/api/v1/push")
if [[ "$push_status" != "204" ]]; then
  echo "smoke_test: FAIL — push returned HTTP $push_status (expected 204)" >&2
  exit 1
fi
echo "smoke_test: OK — push HTTP 204"

# Loki's query API needs a small lag for the WAL to flush + the push to
# become queryable. Poll for up to 60s.
echo "smoke_test: polling /loki/api/v1/query_range for the payload"
deadline=$(( $(date +%s) + 60 ))
while (( $(date +%s) < deadline )); do
  start_ns=$(( NS_NOW - 60000000000 ))    # NS_NOW - 60s
  end_ns=$(( NS_NOW + 60000000000 ))      # NS_NOW + 60s
  body=$("${KCTL[@]}" -n "$NS" exec loki-curl -- \
      curl -s --get \
      --data-urlencode 'query={app="rules_loki_smoke"}' \
      --data-urlencode "start=${start_ns}" \
      --data-urlencode "end=${end_ns}" \
      --data-urlencode "limit=50" \
      "http://${LOKI_HOST}/loki/api/v1/query_range")
  if grep -qF "$PAYLOAD" <<<"$body"; then
    echo "smoke_test: OK — Loki returned the pushed payload"
    exit 0
  fi
  sleep 2
done

echo "smoke_test: FAIL — payload never appeared in /loki/api/v1/query_range response" >&2
echo "---- last response body ----" >&2
echo "$body" >&2
echo "---- loki pod state ----" >&2
"${KCTL[@]}" -n loki get pods >&2 || true
"${KCTL[@]}" -n loki logs sts/loki --tail=50 >&2 || true
exit 1
