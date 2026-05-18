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
| `grafana-cloud-credentials` | `PROM_REMOTE_WRITE_URL`, `PROM_USER`, `PROM_PASS`, `LOKI_PUSH_URL`, `LOKI_USER`, `LOKI_PASS` | grafana-alloy |
| `tailscale-oauth` | `TS_OAUTH_CLIENT_ID`, `TS_OAUTH_CLIENT_SECRET` | tailscale-operator (in realtà passato via helm install, vedi `bootstrap/install.sh`) |

Tutti i secret applicativi vivono nel namespace `burraco`. Quelli infra nel rispettivo namespace (`infra`, `observability`).

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
