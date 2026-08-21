# burraco-gitops

GitOps source-of-truth per il deployment di AI-Burraco su k3s single-node.

ArgoCD osserva questo repo e riconcilia il cluster di conseguenza. Niente `kubectl apply` manuale, niente SSH per deploy.

## Layout

```
burraco-gitops/
├── bootstrap/                  # one-shot, eseguito a mano la prima volta
│   ├── install.sh              # installa k3s addons che ArgoCD non può gestire da sé
│   ├── cluster-issuer.yaml     # Let's Encrypt HTTP-01
│   └── root-app.yaml           # app-of-apps che chiude il loop GitOps
├── apps/                       # gestito da ArgoCD (root-app punta qui)
│   ├── infra/                  # postgres, redis, redpanda, traefik, alloy
│   └── services/               # ApplicationSet per gli 8 Spring Boot + web
├── charts/
│   ├── spring-microservice/    # un chart parametrizzato per tutti gli 8 backend
│   ├── nextjs-web/             # chart per il frontend Next.js
│   └── node-service/           # chart generico per servizi Node.js (agent_stream_notifier)
└── environments/
    └── prod/
        ├── values-*.yaml       # uno per servizio (image tag, env specifici)
        ├── infra/              # values per i chart infrastrutturali
        └── secrets/            # SealedSecret cifrati (safe da committare)
```

## Bootstrap iniziale (una sola volta per cluster)

Prerequisito: VPS con k3s installato e `kubectl` configurato in locale (vedi `PIANO_MIGRAZIONE_GITOPS.md` Fase 1).

```bash
# Dal repo gitops checkato in locale
./bootstrap/install.sh
```

Lo script installa: ArgoCD, Sealed Secrets controller, cert-manager, Tailscale Operator, e applica `bootstrap/root-app.yaml` (l'app-of-apps che a quel punto prende in carico tutto il resto).

## Aggiungere un nuovo servizio

### Servizio Spring Boot

1. Crea `environments/prod/values-{nome}.yaml` (copia da `values-identity-service.yaml`).
2. Aggiungi `{nome}` alla lista in `apps/services/backend-applicationset.yaml`.
3. Commit → push → ArgoCD lo deploya in ~1 minuto.

Niente altro: il chart `charts/spring-microservice` copre tutti i servizi Spring Boot via parametri.

### Servizio Node.js (es. agent_stream_notifier)

1. Crea `environments/prod/values-{nome}.yaml` (copia da `values-agent-stream-notifier.yaml`).
2. Aggiungi un `Application` dedicato in `apps/services/{nome}.yaml` (copia da `agent-stream-notifier.yaml`).
3. Sigilla i token richiesti come SealedSecret (vedi `environments/prod/secrets/README.md`).
4. Commit → push → ArgoCD lo deploya.

Il chart `charts/node-service` è il corrispettivo generico per i servizi Node (niente Spring/JVM).

## Aggiornare l'immagine di un servizio (deploy)

La pipeline CI del repo applicativo apre una PR su questo repo che cambia `image.tag` in `environments/prod/values-{nome}.yaml`. Tu fai merge manuale; ArgoCD riconcilia.

## Gestione secret

I secret si committano cifrati come `SealedSecret`. Per crearne uno:

```bash
echo -n "valore-segreto" | kubectl create secret generic mio-secret \
  --dry-run=client --from-file=key=/dev/stdin -o yaml | \
  kubeseal --controller-namespace=kube-system -o yaml > \
  environments/prod/secrets/mio-secret.sealed.yaml
```

La chiave master del controller Sealed Secrets va **esportata una sola volta** e archiviata offline (password manager). Vedi `PIANO_MIGRAZIONE_GITOPS.md` Fase 2.2.

## Accesso ad ArgoCD UI

Solo via Tailscale: https://argocd.tailc1547d.ts.net
Devi essere loggato sul tuo tailnet con un device autorizzato. Niente DNS pubblico, niente attack surface.
