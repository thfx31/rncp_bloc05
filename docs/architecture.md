# Architecture — vue d'ensemble

## Contexte et problématique

Thomas est en alternance dans une équipe infrastructure d'une entreprise du
secteur spatial/satellite, en support à des développeurs de logiciel embarqué
C. Les toolchains et simulateurs de build dépendent d'OS obsolètes (CentOS 7,
Ubuntu 18.04/20.04) : ça impose des workstations et des nodes Jenkins dédiés,
figés par OS, non patchables sans casser les builds.

**Objectif du POC** : dockeriser ces environnements de build et les orchestrer
sur Kubernetes, avec une chaîne CI/CD sécurisée (DevSecOps) de bout en bout —
tout en gardant un scope tenable pour une démo de 5 minutes devant jury.

Le cas d'usage applicatif (`app/firmware-poc/`) est **volontairement
fictif** : le code réel et les outils de l'entreprise ne peuvent pas sortir du
cadre professionnel (confidentialité industrielle). Le firmware C ciblant ARM
Cortex-M reproduit fidèlement le problème réel (deux toolchains, deux OS)
sans exposer quoi que ce soit de sensible — cf. `docs/firmware-poc.md`.

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
        │                  Scaleway (cloud public)                   │
        │                                                             │
        │   ┌─────────────┐        ┌─────────────────────────────┐  │
        │   │  VM Vault   │        │      Cluster RKE2 (3 nodes)  │  │
        │   │  (externe)  │◄──────►│  control-plane + 2 workers   │  │
        │   └─────────────┘  net.  │  Cilium (CNI) + Hubble        │  │
        │                   privé  │                                │  │
        │                          │  ArgoCD (App-of-Apps GitOps)  │  │
        │                          │   ├─ layer-00-infra           │  │
        │                          │   │   CCM, ingress-nginx,     │  │
        │                          │   │   cert-manager             │  │
        │                          │   ├─ layer-01-apps            │  │
        │                          │   │   Harbor, GitLab,          │  │
        │                          │   │   SonarQube, Jenkins        │  │
        │                          │   └─ layer-02-observability   │  │
        │                          │       kube-prometheus-stack,   │  │
        │                          │       Loki/Promtail            │  │
        │                          └─────────────────────────────┘  │
        └───────────────────────────────────────────────────────────┘
                                        │ *.k8s.yplank.fr (wildcard, OVH DNS)
                                        ▼
                              Utilisateur / jury (navigateur)
```

## Flux CI/CD applicatif

```
git push (GitLab, projet poc-ci/firmware-poc)
   │  webhook
   ▼
Jenkins (agent Kubernetes dynamique, legacy Ubuntu 18.04/gcc-7
         ou modern Ubuntu 22.04/gcc-12 selon paramètre VARIANT)
   ├─ Checkout
   ├─ Checkov       — lint sécurité du Dockerfile
   ├─ Build image   — si Dockerfile modifié, sinon pull Harbor
   ├─ Trivy         — scan vulnérabilités, FAIL sur HIGH/CRITICAL
   ├─ Syft          — génère le SBOM (SPDX)
   ├─ Build firmware — compilation dans le conteneur (legacy ou modern)
   ├─ SonarQube     — analyse statique + Quality Gate
   ├─ Simulateur    — validation du binaire ELF produit
   ├─ Push Harbor   — image versionnée + latest
   └─ Cosign        — signe l'image + atteste le SBOM
```

Détail complet : `docs/firmware-poc.md` et `docs/apps-stack.md`.

## Pourquoi ces choix (arguments pour l'oral)

- **RKE2 plutôt que kubeadm** : CIS-hardened par défaut, install air-gap
  possible (pertinent en environnement confidentiel), upgrades simplifiés.
- **Cilium** malgré le CNI par défaut de RKE2 : eBPF, Hubble (observabilité
  réseau), NetworkPolicy L7.
- **Pas de Longhorn / débat stockage** : hors scope de démo, choix
  d'implémentation silencieux (`local-path-provisioner`).
- **Vault hors cluster** (VM dédiée) : éviter la dépendance circulaire — si le
  cluster tombe, il faut pouvoir accéder aux secrets pour le réparer.
- **Scaleway (cloud public)** plutôt qu'un homelab : garantit la disponibilité
  le jour J. L'IaC (Terraform + Ansible) est identique à ce qui serait
  déployé on-premise, seul le provider change.
- **Cas d'usage fictif** : confidentialité industrielle — cf. ci-dessus.
- **Argument GitOps** : le cluster peut être détruit et recréé
  (`docs/rebuild-runbook.md`), toute la stack applicative revient
  automatiquement sans intervention manuelle — preuve concrète de
  reproductibilité et de résilience de l'approche IaC + GitOps.

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

## Sécurité / DevSecOps — état des lieux

| Brique | Statut | Détail |
|---|---|---|
| Trivy | Implémenté | Scan d'image dans le pipeline Jenkins, fail sur HIGH/CRITICAL. Bundlé aussi dans Harbor |
| Cosign | Implémenté | Signature des images validées, clé statique (cf. `docs/cosign.md`) |
| Syft (SBOM) | Implémenté | Génération SBOM par image, attaché en attestation Cosign |
| Checkov / tfsec | Implémenté | Scan Dockerfile dans Jenkins (Checkov) + scan Terraform/Ansible via GitHub Actions (`docs/checkov-tfsec.md`) |
| SonarQube | Implémenté | Déjà en place chez le client, gardé dans le POC |
| RBAC K8s | Implémenté | Namespaces séparés par app, ServiceAccounts scopés |
| NetworkPolicy Cilium | Implémenté (silencieux) | Isolation inter-namespaces par défaut de Cilium, non démontrée activement |
| Vault | Implémenté (partiel) | VM dédiée, single-node raft, unseal manuel (limite POC assumée) — secrets KV gérés manuellement, pas d'auth K8s dynamique (cf. `docs/evolutions-possibles.md`) |
| Kyverno | Non implémenté | Admission control envisagé (`verifyImages` sur signature Cosign) — cf. `docs/evolutions-possibles.md` |
| ESO (External Secrets Operator) | Non implémenté | cf. `docs/evolutions-possibles.md` |
| Gitleaks | Abandonné | Pas de scan de secrets dans le code applicatif dans ce POC |

## Points de langage à tenir prêts pour l'oral

- **Pourquoi Kyverno n'est pas implémenté alors que Cosign signe déjà tout ?**
  Cosign sécurise la sortie du pipeline (preuve cryptographique), Kyverno
  sécuriserait l'entrée du cluster (bloquer un `kubectl apply` manuel qui
  contourne le pipeline) — defense in depth. Piste connue, non implémentée
  par arbitrage de risque/valeur pour un POC de démo 5 minutes (cf.
  `docs/evolutions-possibles.md`).
- **Pourquoi Vault n'a pas d'auth K8s dynamique ?** Même arbitrage — la
  reachability réseau et la gestion des tokens de ServiceAccount sur K8s
  récent n'avaient jamais été validées sur ce cluster ; le risque de debug
  supplémentaire sur une brique périphérique (non démontrée à l'oral)
  n'était pas justifié.
- **Pourquoi un use-case fictif ?** Confidentialité industrielle.
- **Pourquoi pas de mutualisation multi-départements (scénario "Centre de
  Services") ?** Trop lourd à poser et défendre en 45 minutes pour la valeur
  ajoutée obtenue — le fil conducteur reste le contexte réel de
  l'alternance (une équipe, un périmètre).
