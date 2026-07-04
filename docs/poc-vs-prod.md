# POC vs Production — arbitrages

Tableau vivant, complété à chaque décision (cf. CONTEXT.md).

## Terraform — découpage des states

| Aspect | Choix POC | Justification |
|---|---|---|
| Racines Terraform | `terraform/cluster/` et `terraform/vault/` séparées, states S3 indépendants (même bucket, clés différentes) | Vault a un cycle de vie indépendant du cluster (cf. CONTEXT.md — "pourquoi Vault hors cluster"). `destroy-cluster.yml` ne doit jamais pouvoir toucher l'état Vault. `terraform/vault/` retrouve le réseau privé du cluster par **data source** (nom), pas par remote state, pour ne pas créer de dépendance dure entre les deux states |
| Ordre de déploiement | `deploy-cluster.yml` avant `deploy-vault.yml` (le réseau privé doit exister) | Documenté ici faute de dépendance Terraform explicite entre les deux racines |

## Fondation cluster — Ansible vs GitOps

| Aspect | Choix POC | Justification |
|---|---|---|
| Périmètre Ansible | S'arrête après un cluster RKE2 up (Phase 1). Aucun rôle Ansible pour CCM/ingress/cert-manager/ArgoCD | Un premier essai avec 6 rôles Ansible custom (un par brique, wrapper `kubernetes.core.helm`) s'est révélé plus lourd que nécessaire pour un POC de démo 5 min — cf. CONTEXT.md. ArgoCD gère nativement Helm, l'ordre (sync-wave) et le self-heal ; réécrire cette logique en Ansible n'ajoutait rien |
| Bootstrap ArgoCD | Un seul `kubectl apply` du manifeste officiel (`stable` channel), pas de chart Helm | Cohérent avec un pattern déjà validé sur un projet précédent ([Ynov_k8s](https://github.com/thfx31/Ynov_k8s)) — plus simple qu'un rôle Ansible + Helm pour un composant qui ne tourne qu'une fois au bootstrap |
| Reste de la fondation (CCM, Hubble, ingress-nginx, cert-manager, webhook OVH) | Manifestes déclaratifs dans `kubernetes/00-infra/`, synchronisés par ArgoCD (App-of-Apps) dès le bootstrap | Le cluster peut être détruit/recréé sans rejouer une séquence Ansible complexe : `make k8s-bootstrap-argocd` suffit, ArgoCD retrouve son état désiré depuis Git |

## Stack applicative (Phase 3) — Harbor, GitLab, SonarQube, Jenkins

| Aspect | Choix POC | Justification |
|---|---|---|
| Stockage | `local-path-provisioner` (Rancher, vendoré), pas de Longhorn | Cohérent avec l'arbitrage déjà pris en Phase 2 (cf. CONTEXT.md — "pas de débat stockage à porter à l'oral"). Découvert en cours de route que RKE2 ne le bundle pas par défaut dans cette configuration — ajouté manuellement en Phase 2 (`kubernetes/00-infra/local-path-provisioner.yaml`) |
| Répartition des apps | `nodeSelector` figé par app (worker-01 vs worker-02), pas d'autoscaling/HA | Cluster à 2 workers de taille modeste (4 vCPU/12 Go) — éviter que Harbor+GitLab+SonarQube+Jenkins ne se concentrent tous sur le même node et OOM. Repris du pattern validé sur l'ancien repo `infra-rncp` |
| Mots de passe admin | Générés aléatoirement via `make k8s-apps-secrets`, jamais commités (mécanismes `existingSecret` natifs de chaque chart) | `rncp_bloc05` est un repo **public** — l'ancien repo `infra-rncp` committait des mots de passe en clair (`Ch4ng3M3!`), acceptable pour un repo privé mais pas ici |
| GitLab — composants désactivés | `registry`, `gitlab-runner`, `prometheus`, `pages`, `kas` désactivés dans le chart | Redondant avec Harbor (registry) et l'observabilité déjà prévue en Phase 5 ; scope POC serré, cf. CONTEXT.md |
| GitLab — version de chart | Figé en `9.11.7`, pas la dernière branche `10.x` | Le chart `10.x` a supprimé les sous-charts PostgreSQL/Redis embarqués (base externe désormais obligatoire) — hors scope pour un POC 5 min, pas de valeur de démo à en tirer. La branche `9.x` reçoit encore des mises à jour de sécurité sur l'image GitLab elle-même |
