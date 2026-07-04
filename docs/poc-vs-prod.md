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
