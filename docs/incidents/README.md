# Incident Reports

Incident reports preserve how an operational symptom was reported, what the
response established, which hypotheses were rejected, and what recurrence risk
remains. They are historical evidence, not current runbooks. Current diagnostic
and recovery steps belong in [`docs/troubleshooting.md`](../troubleshooting.md)
and should link back to the incident that established them.

## Statuses

- **Investigating:** the failure mechanism is not yet established.
- **Diagnosed; remediation open:** the failure mechanism is established, but
  no durable corrective action has been selected or verified.
- **Closed:** the selected corrective action is implemented and its stated
  verification criteria have passed.

Immediate recovery does not by itself justify `Closed`. A report must keep
reported symptoms, direct observations, source-backed behavior, inference, and
open questions distinct. Missing telemetry is an evidence gap, not evidence
that no work or latency occurred.

## Index

| Date | Status | Incident |
|---|---|---|
| 2026-08-27 | Diagnosed; remediation open | [Phoenix experiment timeouts initially reported as a network failure](2026-08-27-phoenix-experiment-timeouts.md) |

## Adding a Report

Use `YYYY-MM-DD-short-title.md`. Include at least the impact, initial report,
timeline, evidence, root cause, contributing factors, rejected hypotheses,
response outcome, and corrective actions. Name the owning repository when a
follow-up crosses the GitOps boundary; an incident in this repository does not
authorize changes in another repository or in the live cluster.
