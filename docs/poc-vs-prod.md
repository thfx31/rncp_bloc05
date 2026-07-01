# POC vs Production — arbitrages

Tableau vivant, complété à chaque décision (cf. CONTEXT.md).

## Terraform — découpage des states

| Aspect | Choix POC | Justification |
|---|---|---|
| Racines Terraform | `terraform/cluster/` et `terraform/vault/` séparées, states S3 indépendants (même bucket, clés différentes) | Vault a un cycle de vie indépendant du cluster (cf. CONTEXT.md — "pourquoi Vault hors cluster"). `destroy-cluster.yml` ne doit jamais pouvoir toucher l'état Vault. `terraform/vault/` retrouve le réseau privé du cluster par **data source** (nom), pas par remote state, pour ne pas créer de dépendance dure entre les deux states |
| Ordre de déploiement | `deploy-cluster.yml` avant `deploy-vault.yml` (le réseau privé doit exister) | Documenté ici faute de dépendance Terraform explicite entre les deux racines |
