# Observabilité (Phase 5) — Prometheus/Grafana + Loki/Promtail

## Quoi

Nouvelle couche GitOps `kubernetes/02-observability/` (sync-wave 2, après
`layer-01-apps`), déclarée dans `kubernetes/argocd-manager/02-observability.yaml`
— même pattern App-of-Apps que les couches précédentes (`docs/cluster-foundation.md`,
`docs/apps-stack.md`).

- **kube-prometheus-stack** (chart `prometheus-community/kube-prometheus-stack`)
  — Prometheus (métriques cluster + apps via ServiceMonitor auto-découverts)
  + Grafana (dashboards, exposé `grafana.k8s.yplank.fr`).
- **loki-stack** (chart `grafana/loki-stack`, `grafana.enabled: false`) — Loki
  (stockage des logs) + Promtail (DaemonSet, collecte les logs de chaque node).
  Grafana de kube-prometheus-stack sert de dashboard unique pour les deux
  (datasource Loki ajoutée via `grafana.additionalDataSources`).

## Secret admin Grafana — `make k8s-monitoring-secrets`

Mot de passe généré aléatoirement, jamais committé, même mécanisme
idempotent que `make k8s-apps-secrets` :

```bash
make k8s-monitoring-secrets   # à lancer après make k8s-bootstrap-argocd
```

```bash
# Récupérer le mot de passe si perdu (tant que le cluster tourne)
kubectl get secret grafana-admin-secret -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

## Arbitrages POC (cf. `docs/poc-vs-prod.md`)

- **Alertmanager désactivé** — aucune alerte à faire remonter dans ce POC de
  démo, pas de canal de notification (mail/Slack/PagerDuty) à configurer pour
  un environnement de démo temporaire.
- **Rétention Prometheus courte (12h)** et stockage `local-path` réduit (5Gi
  Prometheus, 5Gi Loki) — cohérent avec un cluster détruit/recréé à chaque
  session, pas besoin d'historique long.
- **Placement `worker-02`** (Prometheus, Grafana, Loki) — `worker-01` porte
  déjà Harbor/GitLab/agents Jenkins ; `worker-02` (SonarQube + Jenkins
  controller) a plus de marge. Promtail (DaemonSet) n'a volontairement pas
  de `nodeSelector` : il doit tourner sur chaque node pour en collecter les
  logs.

## Démo

Se connecter en `admin` + mot de passe ci-dessus sur
`https://grafana.k8s.yplank.fr`. Dashboards bundlés par le chart, à utiliser
dans cet ordre pour raconter "le cluster tourne, voici où, voici quoi,
voici la preuve" :

1. **`Kubernetes / Compute Resources / Cluster`** — vue d'ensemble, point
   d'entrée pour situer le contexte.
2. **`Node Exporter / Nodes`** — vue par node (CPU/RAM/disque/réseau) : les 3
   nodes (control-plane + 2 workers) avec une vraie charge.
3. **`Kubernetes / Compute Resources / Namespace (Pods)`** — sélectionner le
   namespace `jenkins` ou `harbor` pour montrer les pods réels de la stack
   applicative (agents Jenkins éphémères pendant un build, par exemple).
4. **Explore → datasource Loki** — requête live sur les logs d'un pod
   Jenkins/Harbor, argument audit trail.

## Piège rencontré — node-exporter injoignable (`no route to host`)

Prometheus ne pouvait pas scraper `node-exporter` sur les workers
(dashboard "Node Exporter / Nodes" vide) : le port `9100/tcp` n'était jamais
ouvert dans `firewalld` (rôle Ansible `security`), node-exporter n'existant
pas avant cette phase. Corrigé dans
`ansible/roles/security/tasks/main.yml` — s'applique automatiquement au
prochain rebuild complet.
