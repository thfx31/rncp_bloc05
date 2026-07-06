# RNCP39582 — Expert en architecture des systèmes d'information
### Bloc de compétence BC05 — Concevoir et mettre en œuvre l'architecture d'un SI

Projet de Mastère **Expert en cloud, sécurité & infrastructure** — Modernisation d'une chaîne CI/CD industrielle avec Kubernetes, Infrastructure as Code et DevSecOps.

## Contexte

Les toolchains et simulateurs de build d'une équipe infrastructure (secteur spatial/satellite)
dépendent d'OS obsolètes (Ubuntu 18.04/20.04) : ça impose des workstations et des nodes Jenkins
dédiés, figés par OS, non patchables sans casser les builds.

Ce POC dockerise ces environnements de build et les orchestre sur Kubernetes, avec une chaîne
CI/CD sécurisée (DevSecOps) de bout en bout — cas d'usage volontairement fictif (confidentialité
industrielle), détail complet dans [`docs/architecture.md`](docs/architecture.md).

## Stack technique

| Couche | Outil | Rôle |
|---|---|---|
| Provisionnement | Terraform (provider Scaleway) | VM control-plane/workers/Vault |
| Configuration | Ansible | Bootstrap OS, RKE2, Vault |
| Orchestration | Kubernetes (RKE2) | Plateforme d'exécution |
| Réseau | Cilium + Hubble | CNI, observabilité réseau |
| Ingress | NGINX Ingress + cert-manager | Routage HTTPS, certificats Let's Encrypt (DNS-01 OVH) |
| GitOps | ArgoCD (App-of-Apps) | Déploiement déclaratif |
| Source Control | GitLab | Code applicatif (firmware-poc) |
| CI/CD | Jenkins | Pipeline build/scan/signature |
| Registry | Harbor | Stockage et scan d'images (Trivy intégré) |
| Qualité | SonarQube | Analyse statique du code C |
| Secrets | Vault (VM dédiée) | Coffre-fort central, KV manuel dans ce POC |
| Monitoring | kube-prometheus-stack | Métriques cluster et applications (Prometheus + Grafana) |
| Logs | Loki + Promtail | Centralisation des logs, audit trail |
| Sécurité | Trivy, Cosign, Syft, Checkov/tfsec | DevSecOps — scan, signature, SBOM, IaC |

## Pipeline CI/CD

Le use-case métier est un firmware embarqué C fictif, compilé dans deux environnements
conteneurisés (legacy et modernisé) — démontre qu'un node AlmaLinux 9 peut compiler dans
n'importe lequel des deux sans dépendance à l'OS physique, via des agents Kubernetes éphémères.

```
git push (GitLab, projet poc-ci/firmware-poc)
    │  webhook
    ▼
Jenkins (agent Kubernetes éphémère, paramètre VARIANT: legacy|modern)
    ├── 1. Checkout
    ├── 2. Checkov — lint sécurité du Dockerfile
    ├── 3. Build image Docker (legacy Ubuntu 18.04+gcc-7, ou modern Ubuntu 22.04+gcc-12)
    ├── 4. Trivy — scan vulnérabilités, FAIL si HIGH/CRITICAL
    ├── 5. Syft — génère le SBOM (SPDX)
    ├── 6. Compilation firmware dans le conteneur (legacy ou modern)
    ├── 7. SonarQube — analyse statique + Quality Gate
    ├── 8. Simulateur — validation du binaire ELF produit
    ├── 9. Push Harbor — image versionnée + latest
    └── 10. Cosign — signe l'image + atteste le SBOM
```

`VARIANT=legacy` se déclenche automatiquement à chaque push (webhook GitLab).
`VARIANT=modern` se lance à la main (Build with Parameters) — un seul
Jenkinsfile paramétré plutôt que deux jobs dupliqués.

## Structure du dépôt

```
rncp_bloc05/
├── terraform/
│   ├── cluster/            Provisionnement Scaleway — control-plane, workers
│   └── vault/               Provisionnement Scaleway — VM Vault dédiée
├── ansible/
│   ├── bootstrap-k8s.yml    Bootstrap OS + RKE2
│   ├── bootstrap-vault.yml  Bootstrap OS + Vault
│   └── roles/               RKE2, Vault, sécurité (firewalld, SELinux)
├── kubernetes/
│   ├── argocd-manager/      App-of-Apps racine (root-app + 3 couches)
│   ├── 00-infra/            CCM, Cilium/Hubble, ingress-nginx, cert-manager
│   ├── 01-apps/             Harbor, GitLab, SonarQube, Jenkins
│   └── 02-observability/    kube-prometheus-stack, Loki/Promtail
├── app/firmware-poc/         Code C fictif + Dockerfiles legacy/modern + Jenkinsfile
├── scripts/                 gitlab-init.sh (bootstrap projet GitLab + webhook)
├── .github/workflows/       lint-iac.yml (Checkov/tfsec/ansible-lint sur l'IaC)
├── Makefile                 Toutes les commandes de pilotage (make help)
└── docs/                    Documentation technique (voir ci-dessous)
```

## Démarrage rapide

- **Première mise en place** : [`docs/setup-guide.md`](docs/setup-guide.md) — checklist
  détaillée avec l'historique des pièges rencontrés.
- **Reconstruction complète** (après un destroy) : [`docs/rebuild-runbook.md`](docs/rebuild-runbook.md)
  — mode opératoire linéaire à redérouler tel quel.
- `make help` liste toutes les commandes disponibles.

## Documentation

| Doc | Contenu |
|---|---|
| [`docs/architecture.md`](docs/architecture.md) | Vue d'ensemble, schéma, arguments pour l'oral |
| [`docs/poc-vs-prod.md`](docs/poc-vs-prod.md) | Tableau vivant des arbitrages POC vs production |
| [`docs/evolutions-possibles.md`](docs/evolutions-possibles.md) | Pistes envisagées, non implémentées |
| [`docs/setup-guide.md`](docs/setup-guide.md) | Checklist de mise en place, pièges rencontrés |
| [`docs/rebuild-runbook.md`](docs/rebuild-runbook.md) | Runbook de reconstruction complète |
| [`docs/vault.md`](docs/vault.md) | Vault — installation, init, unseal |
| [`docs/cluster-foundation.md`](docs/cluster-foundation.md) | Fondation cluster (GitOps, `00-infra/`) |
| [`docs/apps-stack.md`](docs/apps-stack.md) | Stack applicative (`01-apps/`), credentials, webhook |
| [`docs/monitoring.md`](docs/monitoring.md) | Observabilité (`02-observability/`), dashboards de démo |
| [`docs/firmware-poc.md`](docs/firmware-poc.md) | Cas d'usage applicatif, legacy vs modern |
| [`docs/cosign.md`](docs/cosign.md) | Signature d'images |
| [`docs/checkov-tfsec.md`](docs/checkov-tfsec.md) | Scan statique IaC (GitHub Actions) |
