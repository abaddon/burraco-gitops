Feature: Kafka application topics are provisioned in-cluster via GitOps
  As a platform engineer
  I want application Kafka topics created declaratively through ArgoCD
  So that producer pods can publish events without hitting UNKNOWN_TOPIC_OR_PARTITION errors

  Background:
    Given ArgoCD is reconciling `apps/infra/*.yaml` against the cluster
    And Redpanda is running in the `infra` namespace with no auto-topic creation
    And producer pods are currently logging UNKNOWN_TOPIC_OR_PARTITION errors

  Scenario: ArgoCD sync creates the kafka-topic-init Job
    When an ArgoCD sync is triggered after the manifests are merged to main
    Then a Job named `kafka-topic-init` is created in the `infra` namespace
    And the Job is annotated as an ArgoCD PreSync hook
    And the hook-delete-policy is BeforeHookCreation so prior runs are cleaned up first

  Scenario: Job ensures all required topics exist with correct configuration
    When the `kafka-topic-init` Job runs to completion
    Then each of the following topics exists in Redpanda with at least the specified partition count and replication factor 1:
      | topic                     | partitions |
      | identity.events           | 3          |
      | player.events             | 3          |
      | social.friends            | 3          |
      | social.blocks             | 3          |
      | social.messages           | 3          |
      | lobby.rooms               | 3          |
      | lobby.match-requests      | 3          |
      | game.events               | 6          |
      | ranking.results           | 3          |
      | tournament.events         | 3          |
      | notification.requests     | 3          |
    And the Job exits with status 0

  Scenario: Job is idempotent across repeated syncs
    Given the topics already exist from a prior sync
    When ArgoCD triggers another sync
    Then the Job runs again due to BeforeHookCreation delete policy
    And topic creation uses `--if-not-exists` semantics so no error is raised for pre-existing topics
    And existing topic data and configuration are not modified

  Scenario: Producer pods recover after a successful sync
    Given the kafka-topic-init Job has completed successfully
    When the producer pods reconnect to Redpanda
    Then UNKNOWN_TOPIC_OR_PARTITION log entries drop to zero within one ArgoCD sync cycle
    And no manual kubectl intervention was required to achieve this state

  Scenario: No RBAC escalation is introduced
    When the Job manifest is inspected
    Then the Job uses the `default` ServiceAccount in the `infra` namespace
    And no new ClusterRole or ClusterRoleBinding is created

## Acceptance criteria
- AC-1: A Job manifest exists under `manifests/` and is referenced by an ArgoCD Application in `apps/infra/`; no `kubectl apply` outside ArgoCD is used.
- AC-2: The Job carries `argocd.argoproj.io/hook: PreSync` and `argocd.argoproj.io/hook-delete-policy: BeforeHookCreation` annotations.
- AC-3: All 11 topics listed in the Scenario table are created with the specified partition counts and replication-factor=1.
- AC-4: Topic creation command uses `--if-not-exists` (or equivalent idempotent flag); the Job exits 0 on repeated runs against an already-provisioned cluster.
- AC-5: UNKNOWN_TOPIC_OR_PARTITION entries disappear from producer pod logs within one sync cycle after the manifest is merged.
- AC-6: No new ClusterRole, ClusterRoleBinding, or RBAC resource is introduced; Job runs under `default` SA in `infra` namespace.
- AC-7 (open — must resolve before merge): The 11-topic list above MUST be cross-checked against `common-events/src/main/avro/` in the AI-burraco application repo. The brief specifies 11 topics; the kafka-topics.list in the AI-burraco PR contains 9. Using `--if-not-exists` makes creating more topics than strictly needed safe, but surplus topics must not break consumers. Resolve the discrepancy before this story is marked Done.

## NFR
- latency: Job must complete within 120 seconds of sync start; producer pods must recover within one additional reconciliation cycle (typically < 3 minutes).
- throughput: unknown — needs sales-feedback (topic throughput SLAs are not yet defined for prod).
- error budget: 0 UNKNOWN_TOPIC_OR_PARTITION errors permitted after the first successful sync that includes this Job.
- GitOps-only: every resource is managed exclusively via ArgoCD; no out-of-band kubectl applies.
- Reversible: reverting the manifest commit in git is sufficient to remove the Job from subsequent syncs; previously created topics remain (Kafka topic deletion is a separate, explicit operation).

## Priority
- MoSCoW: must

## Source
- feedback: goal (direct from kickoff brief, 2026-05-26)
