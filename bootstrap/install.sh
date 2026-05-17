#!/usr/bin/env bash
# Bootstrap di un cluster k3s fresh per burraco-gitops.
# Idempotente: rieseguibile senza danni.
set -euo pipefail

ARGOCD_VERSION="v2.13.0"
SEALED_SECRETS_VERSION="v0.27.0"
CERT_MANAGER_VERSION="v1.16.1"

require_env() {
  : "${TS_OAUTH_CLIENT_ID:?Export TS_OAUTH_CLIENT_ID (Tailscale OAuth client ID)}"
  : "${TS_OAUTH_CLIENT_SECRET:?Export TS_OAUTH_CLIENT_SECRET (Tailscale OAuth client secret)}"
  : "${ARGOCD_REPO_PAT:?Export ARGOCD_REPO_PAT (GitHub PAT with repo:read for burraco-gitops)}"
}

install_argocd() {
  echo "==> ArgoCD ${ARGOCD_VERSION}"
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -n argocd -f \
    "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
  kubectl -n argocd rollout status deployment/argocd-server --timeout=5m
}

install_sealed_secrets() {
  echo "==> Sealed Secrets ${SEALED_SECRETS_VERSION}"
  kubectl apply -f \
    "https://github.com/bitnami-labs/sealed-secrets/releases/download/${SEALED_SECRETS_VERSION}/controller.yaml"
  kubectl -n kube-system rollout status deployment/sealed-secrets-controller --timeout=2m

  echo "==> Esporta la chiave master Sealed Secrets (archivia OFFLINE)"
  kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml \
    > "$(dirname "$0")/../sealed-secrets-master-key.BACKUP.yaml"
  echo "    File scritto: bootstrap/../sealed-secrets-master-key.BACKUP.yaml"
  echo "    SPOSTALO ORA in un password manager e cancellalo dal filesystem."
}

install_cert_manager() {
  echo "==> cert-manager ${CERT_MANAGER_VERSION}"
  kubectl apply -f \
    "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"
  kubectl -n cert-manager rollout status deployment/cert-manager --timeout=2m
  kubectl -n cert-manager rollout status deployment/cert-manager-webhook --timeout=2m
  kubectl apply -f "$(dirname "$0")/cluster-issuer.yaml"
}

install_tailscale_operator() {
  echo "==> Tailscale Operator"
  helm repo add tailscale https://pkgs.tailscale.com/helmcharts >/dev/null
  helm repo update >/dev/null
  kubectl create namespace tailscale --dry-run=client -o yaml | kubectl apply -f -
  helm upgrade --install tailscale-operator tailscale/tailscale-operator \
    --namespace tailscale \
    --set-string oauth.clientId="${TS_OAUTH_CLIENT_ID}" \
    --set-string oauth.clientSecret="${TS_OAUTH_CLIENT_SECRET}" \
    --set-string operatorConfig.hostname=burraco-prod-operator
}

register_repo_in_argocd() {
  echo "==> Registra repo gitops in ArgoCD"
  kubectl -n argocd create secret generic burraco-gitops-repo \
    --from-literal=type=git \
    --from-literal=url=https://github.com/abaddon/burraco-gitops \
    --from-literal=username=abaddon \
    --from-literal=password="${ARGOCD_REPO_PAT}" \
    --dry-run=client -o yaml | \
    kubectl label -f - --local=true argocd.argoproj.io/secret-type=repository -o yaml | \
    kubectl apply -f -
}

apply_root_app() {
  echo "==> Apply root app-of-apps"
  kubectl apply -f "$(dirname "$0")/root-app.yaml"
}

print_next_steps() {
  ARGOCD_PWD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "(già ruotata)")
  cat <<EOF

============================================================
Bootstrap completato.

ArgoCD initial admin password: ${ARGOCD_PWD}
  → cambiala subito: argocd account update-password
  → elimina il secret iniziale: kubectl -n argocd delete secret argocd-initial-admin-secret

Accesso UI ArgoCD: https://argocd.tailc1547d.ts.net (richiede Tailscale)
  Se l'hostname non risolve subito, attendi 1-2 minuti che il Tailscale Operator
  registri il device, oppure controlla:
    kubectl -n argocd describe service argocd-server

Da questo momento ogni modifica al cluster passa per Git.
============================================================
EOF
}

main() {
  require_env
  install_argocd
  install_sealed_secrets
  install_cert_manager
  install_tailscale_operator
  register_repo_in_argocd
  apply_root_app
  print_next_steps
}

main "$@"
