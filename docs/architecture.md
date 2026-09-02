# Architecture - vue d'ensemble

## Contexte et problématique

Proposition d'un cluster K8S "pilote" représentatif d'une prodution legacy (machines virtuelles multi OS).
Les toolchains et simulateurs de build dépendent d'OS obsolètes (CentOS 7,
Ubuntu 18.04/20.04) : ça impose des workstations et des nodes Jenkins dédiés,
figés par OS. La conséquence est une maintenance lourde et non durable.

**Objectif du POC** : dockeriser ces environnements de build et les orchestrer
sur Kubernetes, avec une chaîne CI/CD sécurisée (DevSecOps) de bout en bout.

Le cas d'usage applicatif (`app/firmware-poc/`) est **volontairement
fictif** : le code réel et les outils de l'entreprise ne peuvent pas sortir du
cadre professionnel (confidentialité industrielle). Le firmware C ciblant ARM
Cortex-M reproduit fidèlement le problème réel (deux toolchains, deux OS)
 - cf. `docs/firmware-poc.md`.

## Schéma global

```
                         ┌─────────────────────────────┐
                         │      GitHub (IaC)            │
                         │  terraform/ + ansible/        │
                         │  .github/workflows/lint-iac   │
                         └──────────────┬────────────────┘
                                        │ make (Terraform apply / Ansible)
                                        ▼
        ┌───────────────────────────────────────────────────────────┐
        │                  Scaleway (cloud public)                  │
        │                                                           │
        │   ┌─────────────┐        ┌─────────────────────────────┐  │
        │   │  VM Vault   │        │      Cluster RKE2 (3 nodes) │  │
        │   │  (externe)  │◄──────►│  control-plane + 2 workers  │  │
        │   └─────────────┘  net.  │  Cilium (CNI) + Hubble      │  │
        │                   privé  │                             │  │
        │                          │  ArgoCD (App-of-Apps GitOps)│  │
        │                          │   ├─ layer-00-infra         │  │
        │                          │   │   CCM, ingress-nginx,   │  │
        │                          │   │   cert-manager          │  │
        │                          │   ├─ layer-01-apps          │  │
        │                          │   │   Harbor, GitLab,       │  │
        │                          │   │   SonarQube, Jenkins    │  │
        │                          │   └─ layer-02-observability │  │
        │                          │       kube-prometheus-stack,│  │
        │                          │       Loki/Promtail         │  │
        │                          └─────────────────────────────┘  │
        └───────────────────────────────────────────────────────────┘
                                        │ *.k8s.yplank.fr (wildcard, OVH DNS)
                                        ▼
                                   Utilisateur
```

## Flux CI/CD applicatif

```
git push (GitLab, projet poc-ci/firmware-poc)
   │  webhook
   ▼
Jenkins (agent Kubernetes dynamique, legacy Ubuntu 18.04/gcc-7
         ou modern Ubuntu 22.04/gcc-12)
   ├─ Checkout
   ├─ Checkov         - lint sécurité du Dockerfile
   ├─ Build image     - si Dockerfile modifié, sinon pull Harbor
   ├─ Trivy           - scan vulnérabilités, FAIL sur HIGH/CRITICAL
   ├─ Syft            - génère le SBOM (SPDX)
   ├─ Build firmware  - compilation dans le conteneur (legacy ou modern)
   ├─ SonarQube       - analyse statique + Quality Gate
   ├─ Simulateur      - validation du binaire ELF produit
   ├─ Push Harbor     - image versionnée + latest
   └─ Cosign          - signe l'image + atteste le SBOM
```

Détail complet : `docs/firmware-poc.md` et `docs/apps-stack.md`.

## Arbitrage de la démo/PoC

- **RKE2 plutôt que kubeadm** : CIS-hardened par défaut, install air-gap
  possible, upgrades simplifiés.
- **Cilium** malgré le CNI par défaut de RKE2 : eBPF, Hubble (observabilité
  réseau), NetworkPolicy L7.
- **Pas de Longhorn** : hors scope de démo, choix
  d'implémentation silencieux (`local-path-provisioner`).
- **Vault hors cluster** (VM dédiée) : éviter la dépendance au cluster - si le
  cluster tombe, il faut pouvoir accéder aux secrets pour le réparer.
- **Scaleway (cloud public)** plutôt qu'un homelab : garantit la disponibilité
  le jour J. L'IaC (Terraform + Ansible) est proche de ce qui serait
  déployé on-premise, seul le provider change.
- **GitOps** : le cluster peut être détruit et recréé
  (`docs/rebuild-runbook.md`)

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
| Monitoring | kube-prometheus-stack (Prometheus + Grafana) | Métriques cluster et applications |
| Logs | Loki + Promtail | Centralisation des logs, audit trail |

## Sécurité / DevSecOps - état des lieux

| Brique | Statut | Détail |
|---|---|---|
| Trivy | Implémenté | Scan d'image dans le pipeline Jenkins, fail sur HIGH/CRITICAL. Bundlé aussi dans Harbor |
| Cosign | Implémenté | Signature des images validées, clé statique (cf. `docs/cosign.md`) |
| Syft (SBOM) | Implémenté | Génération SBOM par image, attaché en attestation Cosign |
| Checkov / tfsec | Implémenté | Scan Dockerfile dans Jenkins (Checkov) + scan Terraform/Ansible via GitHub Actions (`docs/checkov-tfsec.md`) |
| SonarQube | Implémenté | Déjà en place chez le client, gardé dans le POC |
| RBAC K8s | Implémenté | Namespaces séparés par app, ServiceAccounts scopés |
| NetworkPolicy Cilium | Implémenté (silencieux) | Isolation inter-namespaces par défaut de Cilium, non démontrée activement |
| Vault | Implémenté (partiel) | VM dédiée, single-node raft, unseal manuel (limite POC assumée) - secrets KV gérés manuellement, pas d'auth K8s dynamique (cf. `docs/evolutions-possibles.md`) |
| ESO (External Secrets Operator) | Non implémenté | cf. `docs/evolutions-possibles.md` |
| Gitleaks | Implémenté (repo entier) | GitHub Actions (`gitleaks.yml`), sur tout push/PR - distinct du code applicatif fictif (aucun secret réel possible dans un cas d'usage inventé), ici on protège le repo réel (Terraform/Ansible/scripts) |

## Catégories d'outils de sécurité

| Outil | Catégorie | Ce qu'il analyse |
|---|---|---|
| SonarQube (+ plugin `sonar-cxx` + cppcheck) | SAST (allégé) | Le code source C lui-même - analyse heuristique par fichier (cppcheck), pas de taint analysis inter-fonctions. Limite de l'édition Community, cf. `docs/poc-vs-prod.md` |
| Trivy | SCA (Software Composition Analysis) | Les dépendances/paquets **tiers** présents dans l'image (CVE connues sur des versions de bibliothèques) - pas le code applicatif |
| Checkov (Jenkins) | Scan IaC | Le `Dockerfile` lui-même (mauvaises pratiques d'écriture) |
| tfsec / Checkov (GitHub Actions) | Scan IaC | Terraform/Ansible |
| Gitleaks | Scan de secrets | Recherche de clés/tokens committés dans le repo |

**SAST réel (taint analysis, flux de données inter-procédural)** : non
implémenté ici - limite assumée de SonarQube Community + plugin
communautaire (cf. `docs/poc-vs-prod.md`, section "avantage SonarQube payant
vs Community").
