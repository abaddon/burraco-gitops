Feature: OTel tracing is disabled by default in the spring-microservice chart while the SealedSecret is being verified
  As a platform engineer
  I want `otel.enabled` to default to `false` in the shared Helm chart
  So that Spring services stop emitting "Failed to export" noise caused by an OTLP gateway whose credentials are not yet decrypting in-cluster

  Background:
    Given `charts/spring-microservice/values.yaml` currently has `otel.enabled: true`
    And `environments/prod/secrets/otel-otlp-credentials.sealed.yaml` is not decrypting in-cluster
    And Spring service pods are logging repeated "Failed to export" errors from the OTel exporter
    And ArgoCD reconciles per-service overrides from `environments/prod/values-*.yaml`

  Scenario: Chart default is changed to otel.enabled false
    When the change to `charts/spring-microservice/values.yaml` is merged to main
    Then the file contains `otel.enabled: false` as the default value
    And the file contains a YAML comment dated 2026-05-26 stating the reason (broken SealedSecret) and referencing the reactivation runbook
    And no per-service values file is modified as part of this story

  Scenario: Per-service opt-in override continues to work
    Given a per-service file `environments/prod/values-<service>.yaml` contains `otel.enabled: true`
    When ArgoCD syncs that service
    Then the OTel exporter is active for that service only
    And other services that carry no `otel.enabled` override inherit the chart default of `false`

  Scenario: Failed-to-export noise drops to near-zero after sync
    Given the default has been flipped to `otel.enabled: false` and ArgoCD has synced all affected services
    When a Loki query `{env="prod"} |~ "Failed to export"` is run over a 30-minute window
    Then the query returns fewer results than the pre-change baseline (target: near-zero, defined as fewer than 5 entries per service per hour)
    And no new CrashLoopBackOff events are introduced in the `prod` namespace

  Scenario: Change is git-revertable with no residual side-effects
    When the commit is reverted in git and ArgoCD re-syncs
    Then `otel.enabled` returns to `true` as the chart default
    And services that had no per-service override resume attempting OTel export
    And no cluster state (ConfigMaps, Secrets, Deployments) is left in a permanently modified state

## Acceptance criteria
- AC-1: `charts/spring-microservice/values.yaml` contains `otel.enabled: false` after the change is merged.
- AC-2: The change line is accompanied by a YAML comment containing: the date 2026-05-26, the reason ("SealedSecret otel-otlp-credentials not decrypting in-cluster"), and a reference to the reactivation runbook (runbook path or ticket reference to be filled by the developer).
- AC-3: No `environments/prod/values-*.yaml` file is altered by this story; per-service opt-in remains the documented mechanism for re-enabling OTel.
- AC-4: A Loki query `{env="prod"} |~ "Failed to export"` measured over a 30-minute post-sync window returns fewer than 5 log lines per service per hour (baseline must be recorded before the change for comparison).
- AC-5: No new CrashLoopBackOff or OOMKilled events appear in the `prod` namespace within 30 minutes of the sync completing.
- AC-6: Reverting the commit and re-syncing via ArgoCD fully restores prior behaviour; no manual cluster intervention is required to undo the change.

## NFR
- latency: ArgoCD sync and pod rollout must complete within 5 minutes of merge; log noise must fall within the same sync window.
- throughput: not applicable.
- error budget: fewer than 5 "Failed to export" log lines per service per hour after sync (measured via Loki); 0 new pod restarts attributable to this change.
- GitOps-only: the values.yaml edit is the only required change; no kubectl patches or out-of-band edits.
- Reversible: a single `git revert` commit is sufficient to restore `otel.enabled: true` as the default.

## Priority
- MoSCoW: must

## Source
- feedback: goal (direct from kickoff brief, 2026-05-26)
