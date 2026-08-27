# Phoenix Experiment Timeouts Initially Reported as a Network Failure

| Field | Value |
|---|---|
| Date | 2026-08-27 |
| Status | Diagnosed; remediation open |
| Affected capability | Phoenix server-side dataset experiments |
| Unaffected capability | Direct and Playground requests through the Anthropic OAuth proxy continued to complete |
| GitOps changes during response | None |

## Executive Summary

Phoenix experiments produced either a persisted result near 119 seconds or no
model output. The initial report classified this binary result shape as an
availability, authentication, or transport problem and proposed the Anthropic
OAuth proxy, rate limiting, or token refresh as likely causes.

The incident response did not find a network or authentication failure. Live
proxy health, status counters, logs, Tailscale reachability, Kubernetes health,
and Netdata resource telemetry all contradicted those hypotheses. Phoenix
20.4.0 source and pod logs instead showed that its server-side experiment
runner places a hard 120-second wall-clock deadline around the complete model
stream. When that deadline expires, Phoenix cancels the stream, retries it, and
eventually persists a terminal timeout without partial experiment output or
token usage. Proxy-emitted request spans stored in Phoenix still preserve the
request-to-upstream-header portion of those attempts. The experiment-result
persistence behavior, not the complete observability system, created the
apparently binary outcome.

Output length is the leading reason the characterized Radar prompt crossed the
deadline. A controlled five-run prompt change added a required deliverable
contract and increased mean completion length by about 1,500 tokens, moving
every measured duration above 120 seconds. This result covers one of the eight
dataset examples, not every timed-out stream. The unpersisted attempts remain
censored for stream completion and usage, so their token counts and partial
generation rates are unknown even though header-time proxy spans remain.

## Impact

- Phoenix experiments 1 and 2 stopped with error status after repeated task
  timeouts. Experiment 3 persisted timeout results for its selected examples.
- Most affected examples produced no usable experiment output despite the
  upstream model beginning work on some attempts.
- Experiment results did not retain partial output or completion-token counts.
  Proxy request spans retained header-time evidence, but not stream completion
  or cancellation, and the split evidence surfaces increased diagnosis time.
- No cluster-wide outage, proxy outage, authentication outage, data corruption,
  or workload resource saturation was observed.

## Initial Report

The first diagnosis asserted that runs were either served in approximately 119
seconds or produced nothing, and that this binary shape meant an availability
or authentication failure in the transport rather than a duration or load
problem.

That interpretation treated persisted experiment rows as the complete latency
population. It did not account for a caller-side deadline that discards partial
results. The response therefore investigated transport and infrastructure
first, then reconstructed the Phoenix execution and persistence path.

## Timeline

All times are UTC on 2026-08-27.

| Time | Event |
|---|---|
| 12:13:53 | Experiment 1, `baseline-actor-grounding`, was created. |
| 12:15:53–12:22:00 | Four timeout waves occurred at approximately 120-second intervals, representing the initial attempt and three retries. Phoenix then tripped the task circuit breaker. |
| 12:25:20 | Experiments 2 and 3 were created. |
| 12:27:21–12:29:20 | One experiment 2 run completed naturally with 8,424 completion tokens in 119.225 seconds. |
| 12:27:20–12:33:27 | Further attempts timed out in approximately 120-second waves. Terminal rows recorded `timeout after 3 retries` without partial output or usage; proxy-project spans retained request-to-header evidence. |
| Later that day | Proxy, Tailscale, pod health, Netdata, Phoenix source, experiment rows, and Playground spans were reviewed read-only. The network hypothesis was rejected and the Phoenix deadline was identified. |

## Evidence

### Phoenix deadline and experiment-result persistence behavior

The live Deployment ran
`docker.io/arizephoenix/phoenix:version-20.4.0-nonroot`. In the exact source for
that release:

- `TaskWorkItem` defaults to a 120-second timeout.
- `anyio.fail_after(self._timeout)` wraps iteration over the complete
  `chat_completion_create` stream.
- Timeout handling is separate from rate-limit and transient-error handling.
- The task is retried three times before a terminal timeout result is
  persisted.
- The timeout path does not persist the partial output or token usage that the
  experiment success path writes.

See the exact-version
[`TaskWorkItem` constructor](https://github.com/Arize-ai/phoenix/blob/a015c6f69ccb23f1eb2d2a31a25097b42f9dba00/src/phoenix/server/daemons/experiment_runner.py#L371-L420),
[`fail_after` boundary](https://github.com/Arize-ai/phoenix/blob/a015c6f69ccb23f1eb2d2a31a25097b42f9dba00/src/phoenix/server/daemons/experiment_runner.py#L574-L610),
[success persistence path](https://github.com/Arize-ai/phoenix/blob/a015c6f69ccb23f1eb2d2a31a25097b42f9dba00/src/phoenix/server/daemons/experiment_runner.py#L659-L714),
and [terminal retry handling](https://github.com/Arize-ai/phoenix/blob/a015c6f69ccb23f1eb2d2a31a25097b42f9dba00/src/phoenix/server/daemons/experiment_runner.py#L1867-L1904).

Phoenix logs contained 64 matching `TaskWorkItem ... timed out` entries across
the retry waves. The timing aligned with the source-level 120-second boundary,
not with authentication refusal or immediate connection failure.

### Evidence layers and retry correlation

A later review corrected the initial assertion that timed-out attempts left no
spans anywhere. The evidence was split across three Phoenix surfaces, and the
experiment-result layer censored the attempts' partial response data:

| Evidence surface | Retained evidence | Missing evidence |
|---|---|---|
| Playground `ChatCompletion` spans | Full outputs, completion latency, and token usage for 11 completed manual runs | Evidence for other unmeasured attempts |
| `anthropic-oauth-proxy` project spans | Proxy request occurrence, request-to-upstream-header latency, and span status during timeout windows | Stream completion, token usage, partial output, and downstream cancellation |
| Experiment results | Completed results and terminal timeout records | Partial output, partial usage, and useful elapsed-stream progress for timed-out attempts |

Proxy `proxy_request` spans correlated with the incident cadence. Batches of
eight spans appeared at 12:15:54.418–12:15:55.862,
12:17:56.457–12:17:57.901, and 12:20:00.479–12:20:01.921. A later batch began
at 12:25:20.280 alongside experiments 2 and 3. The spans were `OK` and lasted
approximately 1.0–1.7 seconds.

These spans show that the corresponding requests reached the proxy and
received acceptable upstream response headers. They do not show that the
streamed bodies completed: the proxy ends this instrumentation at header time.
The correlation therefore strengthens rejection of authentication, rate-limit,
and immediate transport-refusal hypotheses without measuring the cancelled
portion of each stream. The displayed batches are strong attempt-level
correlation; the project-wide trace count alone is not proof that every one of
the 64 runner timeout events has a matching proxy span.

### Proxy and network path

At investigation time, the proxy reported two available accounts, zero cooling
down, zero disabled, zero recorded errors, and 223 requests served during the
current process lifetime. Its status counters contained 194 responses with
status 200, 28 with status 400, and one with status 404. There were no 401,
403, 429, 502, 503, or 504 series and no token-refresh failure, upstream-error,
quota-exhaustion, or pool-failover series.

The sampled 24-hour proxy logs contained 44 `/v1/messages` completion records:
26 status 200 and 18 status 400. Their logged latencies ranged from 829 to
8,129 milliseconds. These records did not measure complete stream duration:
the deployed proxy logs `request completed` after upstream response headers
arrive and before returning the streaming body. See the deployed
[`proxy.rs`](https://github.com/basher83/tailnet-microservices/blob/3b30262f2cb0901b3285cc3df30a234bc30ab989/services/oauth-proxy/src/proxy.rs#L350-L490).

The Tailscale ingress backend was reachable over TCP and the tailnet health
endpoint responded successfully. One WireGuard handshake warning appeared in
the preceding 24 hours, but its timestamp did not correlate with the
experiment failures.

### Workload resources

During the 12:20–12:45 UTC incident window, Netdata showed:

| Workload | CPU | Memory | Pressure or throttling |
|---|---:|---:|---|
| Phoenix | Peak about 24.33% of its 1 CPU limit | About 775–804 MiB of a 2 GiB limit | None observed |
| Anthropic OAuth proxy | Peak about 1.76% of its 500m CPU limit | About 26.3–27.4 MiB of a 128 MiB limit | None observed |

Both pods were Ready with zero restarts. This evidence rejects local CPU or
memory saturation as the incident cause. It does not, by itself, rule out
provider-side queueing or model-generation variance.

### Completed-run timing

Phoenix's Playground spans cover substantially the same interval as the
experiment timeout. The span starts before the provider request, ends only
after stream consumption finishes, and records usage on Anthropic's final
`message_stop`. See the exact-version
[`PlaygroundClient` span lifecycle](https://github.com/Arize-ai/phoenix/blob/a015c6f69ccb23f1eb2d2a31a25097b42f9dba00/src/phoenix/server/api/helpers/playground_clients.py#L190-L239)
and [Anthropic stream handling](https://github.com/Arize-ai/phoenix/blob/a015c6f69ccb23f1eb2d2a31a25097b42f9dba00/src/phoenix/server/api/helpers/playground_clients.py#L2420-L2501).

Eleven manual runs characterized dataset example 38, the Radar MCP prompt:

| Group | Runs | Mean latency | Mean completion tokens | Result against 120 seconds |
|---|---:|---:|---:|---|
| Baseline | 1 | 124.590 s | 9,134 | Above |
| P, before deliverable contract | 5 | 114.689 s | 8,448 | Three below, two above |
| C, after deliverable contract | 5 | 135.364 s | 9,950.4 | All above |

The C prompt was exactly the P prompt plus a 1,306-character, 225-word
deliverable suffix. Prompt tokens increased from 787 to 1,228. Across the ten
controlled runs, the completion-token mean increased by 1,502.4 tokens. Of
that increase, about 375.6 tokens were additional thinking tokens and 1,126.8
were the non-thinking output-token remainder.

Across all 11 manual runs, completion count explained about 96.3% of latency
variance. This is strong evidence that output length dominated latency for the
characterized example. It does not characterize the failed attempts for the
other seven dataset examples because neither the experiment results nor the
header-time proxy spans retain stream-completion usage.

The one successful server-side experiment run completed naturally with 8,424
completion tokens in 119.225 seconds, or about 14.153 milliseconds per token.
That observed rate implies only about 8,479 tokens fit into 120 seconds if the
same average rate holds. It is an operational estimate, not a Phoenix token
limit: the enforced mechanism remains wall-clock time.

## Root Cause

Phoenix 20.4.0's server-side experiment runner enforced a hard 120-second
wall-clock deadline around the entire streamed model response. Streams that did
not finish before that deadline were cancelled. After the initial attempt and
three retries, Phoenix persisted a terminal timeout without partial output,
token usage, or a completed experiment result. Proxy request spans still
preserved request-to-header timing. That caller-side cancellation and
experiment-result persistence behavior caused the apparent served-or-missing
shape in the experiment table.

For dataset example 38, the required deliverable contract was a demonstrated
contributing trigger: it increased output length enough that all five measured
durations crossed the deadline. The evidence does not establish output length
as the cause for every other censored stream.

## Contributing Factors

- Experiment results did not preserve partial output, token counts, or useful
  elapsed-stream progress, hiding evidence of work already performed.
- Proxy logs and spans measured time to upstream response headers, not stream
  completion or downstream cancellation.
- Evidence was split across Playground spans, the proxy trace project, and
  experiment results; the initial review did not query all three surfaces.
- Phoenix and proxy logs lacked a shared request identifier for exact
  cross-component correlation.
- The initial diagnosis treated absence of a persisted result as absence of
  partial latency.
- The manual throughput sample covered one dataset example in three short time
  windows, not a broad time-of-day or failed-stream population.
- The deliverable contract placed its evidence table last, making truncation a
  particularly poor substitute for concise generation.

## Rejected Hypotheses

| Hypothesis | Disposition | Basis |
|---|---|---|
| OAuth proxy authentication failure | Rejected for this incident | Healthy accounts, successful refreshes, no 401/403 series, and correlated `OK` proxy spans |
| Rate limiting or quota exhaustion | Rejected for this incident | No 429, quota-exhaustion, cooldown, or failover evidence; timeout-wave proxy spans reached upstream headers |
| Proxy or Tailscale availability failure | Rejected for this incident | Healthy endpoint, reachable backend, correlated request-to-header spans, and no correlated ingress error |
| Phoenix or proxy CPU/memory saturation | Rejected for this incident | Resource headroom with no throttling or memory pressure |
| Output length explains every timeout | Open | Strong for example 38 and consistent with one successful experiment run; failed streams for other examples are censored |
| Provider-side queueing or generation variance | Open but not required to explain example 38 | Completed manual runs were stable; failed-stream TTFT and partial throughput were not retained |

## Response Outcome

The incident was reclassified from a reported network/authentication failure to
a Phoenix experiment-runner deadline failure. No live resource, GitOps
manifest, proxy configuration, token, rate limit, or Tailscale policy was
changed. The diagnosis is complete; recurrence risk remains because the
120-second deadline and the long-output prompt contract are unchanged.

## Corrective Actions

These are follow-up candidates, not authorized or implemented changes.

| Action | Owner boundary | Status | Verification gate |
|---|---|---|---|
| Verify whether Phoenix's client SDK experiment path bypasses the server runner's 120-second deadline | Experiment operator | Open | One unchanged long case completes through the SDK with full span, output, and token usage |
| Test a shorter deliverable contract without using a low output ceiling | Prompt/evaluation work | Open | Repeated manual and server-side runs finish below 120 seconds while retaining required evidence coverage |
| Determine whether a supported Phoenix release exposes a configurable task timeout; otherwise propose an upstream configuration option | Phoenix deployment/upstream | Open | Exact chart and app source show a supported setting, and a bounded test completes beyond 120 seconds without a source fork |
| Add stream-end, downstream-cancel, and shared request/trace identifiers to proxy telemetry | `tailnet-microservices` | Open, separate repository | One request can be correlated from Phoenix start through proxy headers to stream completion or cancellation |
| Preserve partial experiment timeout telemetry in Phoenix or raise an upstream issue | Phoenix upstream | Open | A timed-out attempt retains elapsed stream progress and partial usage without being misclassified as success |

Do not use an approximately 8,000-token `max_tokens` cap as the primary fix.
Anthropic defines `max_tokens` as an absolute generation ceiling and reports
`stop_reason: max_tokens` when it truncates a response. Adaptive thinking also
consumes output tokens, so the point of truncation would not reliably preserve
the final evidence table. See Anthropic's
[stop-reason guidance](https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons).

## Lessons

1. A binary persisted outcome does not prove a binary transport outcome. Check
   caller deadlines and persistence paths before assigning a network cause.
2. Missing experiment output and token counts are censored observations, not
   zero work, zero latency, or transport refusal. Search every telemetry
   project before concluding that no span exists.
3. Correlate source semantics with event timing. The repeated approximately
   120-second waves were more discriminating than the absence of result rows.
4. Distinguish response-header success from complete stream success.
5. Completed-run throughput can identify a leading cause, but header-time
   proxy spans cannot rule out variance later in failed streams whose
   completion was never measured.
6. Record diagnosis and remediation separately. This report does not close the
   recurrence risk or authorize a prompt, Phoenix, or proxy change.

## Current Runbook

See [Phoenix experiments time out while manual Playground runs succeed](../troubleshooting.md#phoenix-experiments-time-out-while-manual-playground-runs-succeed)
for the symptom-shaped diagnostic path.
