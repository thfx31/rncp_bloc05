# POC vs Production — arbitrages

Tableau vivant, complété à chaque décision (cf. `docs/architecture.md`).

## Terraform — découpage des states

| Aspect | Choix POC | Justification |
|---|---|---|
| Racines Terraform | `terraform/cluster/` et `terraform/vault/` séparées, states S3 indépendants (même bucket, clés différentes) | Vault a un cycle de vie indépendant du cluster (cf. `docs/architecture.md` — "pourquoi Vault hors cluster"). `terraform/vault/` retrouve le réseau privé du cluster par **data source** (nom), pas par remote state, pour ne pas créer de dépendance dure entre les deux states |
| Ordre de déploiement | `terraform/cluster` avant `terraform/vault` (le réseau privé doit exister) | Documenté ici faute de dépendance Terraform explicite entre les deux racines |

## Fondation cluster — Ansible vs GitOps

| Aspect | Choix POC | Justification |
|---|---|---|
| Périmètre Ansible | S'arrête après un cluster RKE2 up (Phase 1). Aucun rôle Ansible pour CCM/ingress/cert-manager/ArgoCD | Un premier essai avec 6 rôles Ansible custom (un par brique, wrapper `kubernetes.core.helm`) s'est révélé plus lourd que nécessaire pour un POC de démo 5 min. ArgoCD gère nativement Helm, l'ordre (sync-wave) et le self-heal ; réécrire cette logique en Ansible n'ajoutait rien |
| Bootstrap ArgoCD | Un seul `kubectl apply` du manifeste officiel (`stable` channel), pas de chart Helm | Cohérent avec un pattern déjà validé sur un projet précédent ([Ynov_k8s](https://github.com/thfx31/Ynov_k8s)) — plus simple qu'un rôle Ansible + Helm pour un composant qui ne tourne qu'une fois au bootstrap |
| Reste de la fondation (CCM, Hubble, ingress-nginx, cert-manager, webhook OVH) | Manifestes déclaratifs dans `kubernetes/00-infra/`, synchronisés par ArgoCD (App-of-Apps) dès le bootstrap | Le cluster peut être détruit/recréé sans rejouer une séquence Ansible complexe : `make k8s-bootstrap-argocd` suffit, ArgoCD retrouve son état désiré depuis Git |

## Stack applicative (Phase 3) — Harbor, GitLab, SonarQube, Jenkins

| Aspect | Choix POC | Justification |
|---|---|---|
| Stockage | `local-path-provisioner` (Rancher, vendoré), pas de Longhorn | Pas de débat bare-metal vs cloud à porter à l'oral, ce n'est pas démontré. Découvert en cours de route que RKE2 ne le bundle pas par défaut dans cette configuration — ajouté manuellement en Phase 2 (`kubernetes/00-infra/local-path-provisioner.yaml`) |
| Répartition des apps | `nodeSelector` figé par app (worker-01 vs worker-02), pas d'autoscaling/HA | Cluster à 2 workers de taille modeste (4 vCPU/12 Go) — éviter que Harbor+GitLab+SonarQube+Jenkins ne se concentrent tous sur le même node et OOM. Repris du pattern validé sur l'ancien repo `infra-rncp` |
| Mots de passe admin | Générés aléatoirement via `make k8s-apps-secrets`, jamais commités (mécanismes `existingSecret` natifs de chaque chart) | `rncp_bloc05` est un repo **public** — l'ancien repo `infra-rncp` committait des mots de passe en clair (`Ch4ng3M3!`), acceptable pour un repo privé mais pas ici |
| GitLab — composants désactivés | `registry`, `gitlab-runner`, `prometheus`, `pages`, `kas` désactivés dans le chart | Redondant avec Harbor (registry) et le monitoring dédié (kube-prometheus-stack) ; scope POC serré |
| GitLab — version de chart | Figé en `9.11.7`, pas la dernière branche `10.x` | Le chart `10.x` a supprimé les sous-charts PostgreSQL/Redis embarqués (base externe désormais obligatoire) — hors scope pour un POC 5 min, pas de valeur de démo à en tirer. La branche `9.x` reçoit encore des mises à jour de sécurité sur l'image GitLab elle-même |

## Sécurité (Phase 4) — Cosign

| Aspect | Choix POC | Justification |
|---|---|---|
| Mode de signature | Clé statique (`cosign generate-key-pair`), pas keyless/Sigstore | Pas de dépendance à la joignabilité de `fulcio.sigstore.dev`/`rekor.sigstore.dev` ni à un OIDC issuer externe le jour de la soutenance — démo autonome et fiable |
| Passphrase clé privée | Vide (`COSIGN_PASSWORD=""`) | Permet une signature non-interactive depuis un pipeline Jenkins ; clé privée jamais committée, protégée uniquement par son emplacement hors repo (`~/.cosign/rncp-bc05/`) et les permissions fichier |
| Stockage clé privée | Hors repo (poste opérateur), pas dans Vault | Évite de faire dépendre la capacité de signer d'un Vault unsealed ; piste prod = Vault Transit KMS (`cosign sign --key hashivault://...`), non implémentée ici — cf. `docs/cosign.md` |

## Observabilité (Phase 5) — Prometheus/Grafana + Loki/Promtail

| Aspect | Choix POC | Justification |
|---|---|---|
| Alertmanager | Désactivé | Pas de canal de notification à configurer pour un environnement de démo temporaire, aucune alerte à faire remonter |
| Rétention Prometheus | 12h, stockage `local-path` 5Gi | Cluster détruit/recréé à chaque session — pas besoin d'historique long |
| Placement | `worker-02` (Prometheus, Grafana, Loki) | `worker-01` déjà chargé (Harbor, GitLab, agents Jenkins) ; Promtail (DaemonSet) reste sans `nodeSelector`, doit tourner sur chaque node |

## Sécurité (Phase 4) — Checkov/tfsec (IaC)

| Aspect | Choix POC | Justification |
|---|---|---|
| Sévérité au démarrage | `soft_fail: true` (tfsec, Checkov, `continue-on-error` pour ansible-lint) | Premier scan jamais fait sur ce repo — évite le bruit des faux positifs le temps de les trier. Bascule en hard-fail prévue avant la soutenance |
| Portée | GitHub Actions sur `terraform/`/`ansible/` uniquement, distinct du Checkov Jenkins (scan des Dockerfiles applicatifs) | Deux couches de scan séparées : IaC infra (GitHub, avant `terraform apply`) vs image applicative (GitLab/Jenkins, avant `docker push`) — cf. `docs/checkov-tfsec.md` |

## Sécurité (Phase 4) — Vault K8s auth / Jenkins-Vault / ESO / Kyverno : non implémentés

**Décision (2026-07-06)** : ces briques (auth K8s Vault, Jenkins qui va
chercher un secret dynamiquement, ESO comme pont Vault→K8s Secrets, Kyverno
en admission control) ne sont **pas implémentées** dans ce POC — Vault reste
une VM externe avec des secrets KV gérés manuellement, Jenkins garde ses
credentials en Secrets K8s statiques (`make jenkins-credentials`).

**Pourquoi** : chacune de ces briques dépendait d'éléments jamais validés sur
ce cluster (reachability réseau privé Vault↔API K8s, gestion des tokens de
ServiceAccount long-lived sur K8s récent, TLS auto-signé côté CRD ESO) — un
profil de risque similaire aux incidents déjà rencontrés sur des briques
annexes (webhook GitLab/Jenkins, image Checkov). Aucune de ces briques n'est
le sujet réellement défendu à l'oral (Trivy/Checkov/Cosign le sont) — le
risque de temps de debug supplémentaire sur une brique périphérique n'était
pas justifié par la valeur de démo. Détail des pistes non implémentées :
`docs/evolutions-possibles.md`.

**Argument à l'oral (Q&A)** : Vault est positionné comme coffre-fort central
dès la Phase 1 (VM dédiée, hors cluster, cf. `docs/architecture.md` —
"pourquoi Vault hors cluster") — l'étape naturelle suivante en prod serait
d'activer l'auth K8s pour que les workloads (Jenkins en premier) authentifient
dynamiquement via leur ServiceAccount plutôt que des secrets statiques
copiés, avec ESO comme mécanisme de synchronisation déclaratif, et Kyverno
pour bloquer à l'admission toute image non signée. Piste connue et
argumentable, non implémentée par arbitrage de risque/valeur pour un POC de
démo 5 minutes.
