# Guide de suivi - mise en place infra

Checklist step-by-step, distincte de `docs/runbook-demo.md` (qui sera le script
des 5 minutes de démo, Phase 6/7). Ici : tout ce qu'il faut faire pour avoir un
environnement qui tourne, avec l'historique des pièges déjà rencontrés.

**Pour rejouer un rebuild complet sans repasser par tout l'historique ci-dessous,
voir `docs/rebuild-runbook.md`** - la version pas-à-pas condensée (env vars →
Terraform → Ansible → Vault → GitOps → DNS), pensée pour être redéroulée telle
quelle à chaque destroy/recreate.

## 0. Prérequis Scaleway (manuel, une seule fois)

- [x] Compte Scaleway + projet dédié RNCP
- [x] Clé API IAM (`SCW_ACCESS_KEY` / `SCW_SECRET_KEY`) récupérée
- [x] `SCW_DEFAULT_PROJECT_ID` récupéré
- [x] `SCW_DEFAULT_ORGANIZATION_ID` récupéré
- [x] Clé SSH ajoutée au projet Scaleway (Console -> Project Settings -> SSH Keys)
- [x] Bucket Object Storage `terraform-state-rncp-bc05` créé (Console -> Object
      Storage -> Create Bucket, région `fr-par`, **privé**)
- [x] Policy IAM Object Storage attachée à la clé API

## 1. Variables d'environnement (local)

À exporter dans le shell avant toute commande `terraform` :

```bash
# Provider Scaleway
export SCW_ACCESS_KEY=...
export SCW_SECRET_KEY=...
export SCW_DEFAULT_PROJECT_ID=...
export SCW_DEFAULT_ORGANIZATION_ID=...

# Backend S3 (mêmes valeurs que SCW_ACCESS_KEY/SCW_SECRET_KEY, sous les noms
# que le backend "s3" de Terraform attend réellement)
export AWS_ACCESS_KEY_ID=$SCW_ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$SCW_SECRET_KEY

# Fondation cluster (Phase 2, make k8s-secrets) - DNS-01 OVH pour yplank.fr
export OVH_APPLICATION_KEY=...
export OVH_APPLICATION_SECRET=...
export OVH_CONSUMER_KEY=...
```

## 2. Terraform cluster et vault

Commandes (voir `Makefile` à la racine) :

```bash
make tf-cluster-init        # Initialiser Terraform (cluster)
make tf-cluster-plan        # Planifier les changements (cluster)
make tf-cluster-apply       # Appliquer les changements (cluster)
```

```bash
make tf-vault-init          # Initialiser Terraform (vault)
make tf-vault-plan          # Planifier les changements (vault)
make tf-vault-apply         # Appliquer les changements (vault)
```

## 3. Ansible - bootstrap RKE2

Commandes (voir `Makefile` à la racine) :

```bash
make ansible-inventory  # régénère ansible/tf_outputs.json depuis terraform/cluster
make ansible-k8s        # ansible-playbook bootstrap-k8s.yml (avoir un venv actif)
make kubeconfig         # récupère le kubeconfig du control-plane en local
make nodes              # kubectl get nodes -o wide
```

## 4. Ansible - Vault

Commandes (voir `Makefile` à la racine) :

```bash
make ansible-inventory-vault   # régénère ansible/tf_outputs_vault.json depuis terraform/vault
make ansible-vault             # ansible-playbook bootstrap-vault.yml
```

## 5. Fondation cluster - GitOps

Ansible s'arrête après un cluster RKE2 up (étape 4). CCM Scaleway, Hubble,
ingress-nginx, cert-manager et ArgoCD sont gérés en GitOps - voir `docs/cluster-foundation.md`

Commandes (voir `Makefile` à la racine)

```bash
make k8s-secrets                # Secrets scaleway-secret + ovh-credentials
make k8s-ccm                    # CCM Scaleway - lève le taint uninitialized, requis avant ArgoCD
make k8s-bootstrap-argocd       # ArgoCD + App-of-Apps - prend le relais sur le reste
make k8s-monitoring-secrets     # Secrets Grafana
```

## 6. Stack applicative - Harbor, GitLab, SonarQube, Jenkins

Commandes (voir `Makefile` à la racine)

```bash
make k8s-apps-secrets           # Secrets admin Harbor/GitLab/Jenkins (générés, affichés une fois) + SonarQube passcode
```

## 7. Phases suivantes

Voir `docs/architecture.md` (vue d'ensemble), `docs/poc-vs-prod.md` (arbitrages)
et `docs/evolutions-possibles.md` (pistes non implémentées).
