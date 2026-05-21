# Sealed Secrets

Tutti i secret necessari al cluster vivono qui cifrati come `SealedSecret`.
Sono safe da committare: solo il controller `sealed-secrets-controller` nel cluster ha la chiave privata per decifrarli.

## Secret richiesti

| Nome | Chiavi | Usato da |
|---|---|---|
| `postgres-credentials` | `username`, `password` (CNPG basic-auth) + `SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD` (per Spring) | CNPG Cluster + tutti i servizi Spring |
| `redis-password` | `REDIS_PASSWORD`, `SPRING_DATA_REDIS_PASSWORD` | tutti i servizi Spring + chart redis |
| `jwt-keys` | `JWT_PUBLIC_KEY`, `JWT_PRIVATE_KEY` | identity-service (privata + pubblica), altri servizi (solo pubblica) |
| `brevo-api-key` | `BREVO_API_KEY` | identity-service, notification-service |
| `otel-otlp-credentials` | `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_HEADERS` | tutti i servizi Spring (tracing OTLP) |
| `grafana-cloud-credentials` | `PROM_REMOTE_WRITE_URL`, `PROM_USER`, `PROM_PASS`, `LOKI_PUSH_URL`, `LOKI_USER`, `LOKI_PASS` | grafana-alloy |
| `tailscale-oauth` | `TS_OAUTH_CLIENT_ID`, `TS_OAUTH_CLIENT_SECRET` | tailscale-operator (in realtà passato via helm install, vedi `bootstrap/install.sh`) |

Tutti i secret applicativi vivono nel namespace `burraco`. Quelli infra nel rispettivo namespace (`infra`, `observability`).

## `otel-otlp-credentials` — telemetria OpenTelemetry

I servizi Spring esportano le **tracce** via OTLP (metriche e log restano ad Alloy → Grafana Cloud).
L'endpoint OTLP e l'header di autenticazione del backend sono *operator-supplied*: vanno in questo
SealedSecret, namespace `burraco`, con **esattamente** queste due chiavi — diventano env var perché
il chart `spring-microservice` referenzia il secret via `envFrom`:

| Chiave | Esempio (Grafana Cloud OTLP) |
|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `https://otlp-gateway-prod-eu-west-2.grafana.net/otlp` |
| `OTEL_EXPORTER_OTLP_HEADERS`  | `Authorization=Basic%20<base64(instanceID:token)>` |

> ⚠️ Nel valore di `OTEL_EXPORTER_OTLP_HEADERS` lo spazio va codificato come `%20`: è una lista
> `chiave=valore` separata da virgole, gli spazi letterali la rompono.

Il chart referenzia questo secret come `secretRef` **opzionale** (`optional: true`): finché non lo
sealati i pod partono comunque, ma l'SDK OTel logga warning di export falliti. Sealalo appena
possibile per chiudere quella finestra. Per disattivare del tutto il tracing nel frattempo:
`otel.enabled=false` in `charts/spring-microservice/values.yaml`.

```bash
kubectl create secret generic otel-otlp-credentials \
  --namespace=burraco \
  --from-literal=OTEL_EXPORTER_OTLP_ENDPOINT='https://otlp-gateway-.../otlp' \
  --from-literal=OTEL_EXPORTER_OTLP_HEADERS='Authorization=Basic%20...' \
  --dry-run=client -o yaml | \
  kubeseal --controller-namespace=kube-system \
    --controller-name=sealed-secrets-controller -o yaml \
  > environments/prod/secrets/otel-otlp-credentials.sealed.yaml

git add environments/prod/secrets/otel-otlp-credentials.sealed.yaml
git commit -m "feat(secrets): otel otlp credentials"
```

## Generare un SealedSecret

```bash
# 1. Crea il secret in chiaro localmente (NON committarlo)
kubectl create secret generic postgres-credentials \
  --namespace=burraco \
  --from-literal=POSTGRES_PASSWORD='SuperSegreta123' \
  --from-literal=SPRING_DATASOURCE_USERNAME='postgres' \
  --from-literal=SPRING_DATASOURCE_PASSWORD='SuperSegreta123' \
  --dry-run=client -o yaml > /tmp/postgres-credentials.yaml

# 2. Cifralo con kubeseal (usa la chiave pubblica del cluster di destinazione)
kubeseal --controller-namespace=kube-system \
  --controller-name=sealed-secrets-controller \
  -o yaml < /tmp/postgres-credentials.yaml \
  > postgres-credentials.sealed.yaml

# 3. Cancella il file in chiaro
rm /tmp/postgres-credentials.yaml

# 4. Committa il file *.sealed.yaml
git add postgres-credentials.sealed.yaml
git commit -m "feat(secrets): postgres credentials"
```

## Backup della chiave master

⚠️ **Critico**: se perdi il cluster perdi anche la chiave privata Sealed Secrets, e con essa la capacità di decifrare tutti i `*.sealed.yaml` di questo repo.

Esporta UNA SOLA VOLTA dopo l'installazione:

```bash
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > sealed-secrets-master-key.yaml
```

Salva `sealed-secrets-master-key.yaml` in un password manager / vault offline.
**Non committarlo MAI nel repo.**

## Recovery (se devi reinstallare il cluster)

```bash
# Prima di tutto, applica la chiave master backuppata
kubectl apply -f sealed-secrets-master-key.yaml
# Poi installa il controller normalmente
kubectl apply -f https://github.com/.../controller.yaml
# Riavvia il controller per fargli caricare la chiave esistente
kubectl delete pod -n kube-system -l name=sealed-secrets-controller
```

A questo punto ArgoCD può fare sync del repo e tutti i SealedSecret vengono decifrati correttamente.
