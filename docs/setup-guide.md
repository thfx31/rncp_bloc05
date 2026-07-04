# Guide de suivi — mise en place infra

Checklist step-by-step, distincte de `docs/runbook-demo.md` (qui sera le script
des 5 minutes de démo, Phase 6/7). Ici : tout ce qu'il faut faire pour avoir un
environnement qui tourne.

## 0. Prérequis Scaleway (manuel, une seule fois)

- [x] Compte Scaleway + projet dédié RNCP
- [x] Clé API IAM (`SCW_ACCESS_KEY` / `SCW_SECRET_KEY`) récupérée
- [x] `SCW_DEFAULT_PROJECT_ID` récupéré
- [x] `SCW_DEFAULT_ORGANIZATION_ID` récupéré
- [x] Clé SSH ajoutée au projet Scaleway (Console → Project Settings → SSH Keys) —
      injectée automatiquement dans toutes les instances, rien à référencer dans Terraform
- [x] Bucket Object Storage `terraform-state-rncp-bc05` créé (Console → Object
      Storage → Create Bucket, région `fr-par`, **privé**) — le backend S3 ne le
      crée pas automatiquement, obligatoire avant le premier `terraform init`
- [x] Policy IAM Object Storage attachée à la clé API (le premier essai a échoué
      en `Forbidden` faute de credentials AWS_* réellement exportés dans le shell —
      un profil `[default]` local prenait le relais silencieusement)

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

# Fondation cluster (Phase 2, make k8s-secrets) — DNS-01 OVH pour yplank.fr
export OVH_APPLICATION_KEY=...
export OVH_APPLICATION_SECRET=...
export OVH_CONSUMER_KEY=...
```

Pas besoin de `SCW_DEFAULT_REGION`/`SCW_DEFAULT_ZONE` : chaque ressource fixe
`region`/`zone` explicitement via des variables Terraform déjà par défaut
(`fr-par` / `fr-par-2` dans `terraform/cluster/variables.tf` et
`terraform/vault/variables.tf`).

## 2. Variables futures pour la CI (GitHub Actions) — à faire plus tard, pas maintenant

Mêmes valeurs, mais stockées comme **secrets GitHub Actions** sous ces noms
(le mapping vers `AWS_ACCESS_KEY_ID` etc. se fait dans le YAML du workflow,
pas dans le code Terraform) :

| Secret GitHub | Valeur |
|---|---|
| `SCW_ACCESS_KEY` | = clé API IAM |
| `SCW_SECRET_KEY` | = clé API IAM |
| `SCW_DEFAULT_PROJECT_ID` | = ID projet |
| `TF_BACKEND_ACCESS_KEY` | = même valeur que `SCW_ACCESS_KEY` |
| `TF_BACKEND_SECRET_KEY` | = même valeur que `SCW_SECRET_KEY` |
| `SSH_PRIVATE_KEY` | clé privée correspondant à la clé publique ajoutée au projet Scaleway |

## 3. Ordre de déploiement Terraform

- [x] `terraform/cluster/` : `terraform init` puis `terraform plan` (contrôle),
      puis `terraform apply` — crée le réseau privé, control-plane, workers
- [x] `terraform/vault/` : `terraform init` puis `terraform plan`, puis
      `terraform apply` — **doit venir après** `cluster/`, car le `data` source
      cherche le réseau privé par nom

**Important** : `terraform/cluster` et `terraform/vault` sont détruits en fin de
session (coût Scaleway) et recréés au début de la suivante. À chaque recréation,
rejouer **toute** la séquence ci-dessous dans l'ordre (cluster → vault → Ansible
→ init/unseal Vault) — rien n'est persistant entre deux sessions, y compris le
storage raft de Vault (cf. `docs/vault.md`, section "Rebuild complet à chaque session").

## 4. Ansible — bootstrap RKE2

- [x] Rôle Ansible RKE2 (remplace `kubeadm`) — bootstrap OS, install
      control-plane/agents, récupération kubeconfig

Commandes (voir `Makefile` à la racine) :

```bash
make ansible-inventory  # régénère ansible/tf_outputs.json depuis terraform/cluster
make ansible-k8s        # ansible-playbook bootstrap-k8s.yml
make kubeconfig       # récupère le kubeconfig du control-plane en local
make nodes            # kubectl get nodes -o wide
```

**Pièges rencontrés au premier run** (déjà corrigés dans le repo, gardés ici pour mémoire) :
- `force_path_style` déprécié dans le backend S3 → remplacé par `use_path_style`
  dans les deux `backend.tf`
- SSH `Too many authentication failures` → l'agent SSH proposait plusieurs clés
  avant la bonne ; ajout de `-o IdentitiesOnly=yes` dans `ansible.cfg` (`ssh_args`)
- SSH `Permission denied (publickey)` malgré `IdentitiesOnly=yes` → mauvais nom
  de clé configuré (`id_ed25519` au lieu de `id_ed25519-scw`, la clé réellement
  enregistrée dans le projet Scaleway) ; corrigé dans `ansible.cfg` et
  `inventory.py`

## 5. Ansible — Vault

- [x] Rôle Ansible Vault — install binaire (repo RPM HashiCorp), TLS auto-signée,
      config raft single-node, firewalld, service démarré
- [ ] Init + unseal manuel (voir `docs/vault.md`) — pas automatisé par Ansible,
      volontairement. **À refaire à chaque recréation de la VM Vault** (destroy/
      recreate en fin/début de session) puisque le storage raft ne survit pas à
      l'instance
- [ ] Intégration Jenkins via auth K8s — Phase 4

Commandes :

```bash
make ansible-inventory-vault   # régénère ansible/tf_outputs_vault.json depuis terraform/vault
make ansible-vault     # ansible-playbook bootstrap-vault.yml
```

**Piège supplémentaire rencontré** : module `community.crypto.openssl_certificate` retiré
depuis la v2.0.0 (renommé `x509_certificate`) → corrigé dans `roles/vault/tasks/tls.yml`.
Autre piège : bibliothèque Python `cryptography` absente sur la VM (requise par
`community.crypto`) → ajout d'une installation `python3-cryptography` en tout
début de `tls.yml`.

Statut confirmé : Vault tourne (scellé, non initialisé — attendu, voir `docs/vault.md`
pour la suite manuelle).

## 6. Fondation cluster (Phase 2) — GitOps, pas d'Ansible

Ansible s'arrête après un cluster RKE2 up (étape 4). CCM Scaleway, Hubble,
ingress-nginx, cert-manager et ArgoCD sont gérés en GitOps — voir
`docs/cluster-foundation.md` pour le détail et le pourquoi de ce choix.

```bash
make k8s-secrets           # Secrets scaleway-secret + ovh-credentials
make k8s-ccm               # CCM Scaleway — lève le taint uninitialized, requis avant ArgoCD
make k8s-bootstrap-argocd  # ArgoCD + App-of-Apps — prend le relais sur le reste
```

Repo GitHub **public** (`rncp_bloc05`) — ArgoCD clone en HTTPS anonyme, aucune
credential à enregistrer.

## 7. Phases suivantes

Voir le découpage complet Phase 3 → 7 dans `CONTEXT.md`.
