# Observabilité - Prometheus/Grafana + Loki/Promtail

Nouvelle couche GitOps `kubernetes/02-observability/` (sync-wave 2, après
`layer-01-apps`), déclarée dans `kubernetes/argocd-manager/02-observability.yaml`
- même pattern App-of-Apps que les couches précédentes (`docs/cluster-foundation.md`,
`docs/apps-stack.md`).

- **kube-prometheus-stack** (chart `prometheus-community/kube-prometheus-stack`)
  - Prometheus (métriques cluster + apps via ServiceMonitor auto-découverts)
  + Grafana (dashboards, exposé `grafana.k8s.yplank.fr`).
- **loki-stack** (chart `grafana/loki-stack`, `grafana.enabled: false`) - Loki
  (stockage des logs) + Promtail (DaemonSet, collecte les logs de chaque node).
  Grafana de kube-prometheus-stack sert de dashboard unique pour les deux
  (datasource Loki ajoutée via `grafana.additionalDataSources`).

## Secret admin Grafana - `make k8s-monitoring-secrets`

Mot de passe généré aléatoirement, jamais committé, même mécanisme
idempotent que `make k8s-apps-secrets` :

```bash
make k8s-monitoring-secrets   # à lancer après make k8s-bootstrap-argocd
```

```bash
# Récupérer le mot de passe si perdu (tant que le cluster tourne)
kubectl get secret grafana-admin-secret -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d; echo
```
