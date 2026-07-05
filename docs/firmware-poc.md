# firmware-poc — cas d'usage applicatif (Phase 4/6)

## Quoi

Un firmware fictif pour un sous-système satellite (acquisition de télémétrie,
LED de statut, sortie UART), ciblant ARM Cortex-M — code C minimal
(`app/firmware-poc/src/`), plus un "simulateur" (`simulator/simulator.c`) qui
valide le binaire produit (format ELF, taille, section exécutable) en guise
de test d'intégration sans matériel réel.

## Pourquoi un cas fictif

Le contexte réel (alternance dans une équipe infrastructure du secteur
spatial/satellite, support à des développeurs de logiciel embarqué C) ne
peut pas être démontré avec du vrai code ou de vrais outils — confidentialité
industrielle. Ce cas d'usage reproduit fidèlement le problème réel sans
exposer quoi que ce soit de sensible : voir `CONTEXT.md`.

## Pourquoi deux Dockerfiles (legacy / modern)

Repris de l'ancien repo `infra-rncp` (lecture seule, jamais modifié) :
`docker/Dockerfile.legacy` (Ubuntu 18.04 + gcc-7) et `docker/Dockerfile.modern`
(Ubuntu 22.04 + gcc-12) représentent la **problématique de départ** du
projet : les toolchains de build legacy dépendent d'OS obsolètes, ce qui
imposait historiquement des workstations ou nodes Jenkins dédiés, figés par
OS, non patchables sans casser les builds.

Le `Jenkinsfile` unique (`app/firmware-poc/Jenkinsfile`) est **paramétré**
(`VARIANT: legacy|modern`, cf. `docs/apps-stack.md`) plutôt que dupliqué en
deux fichiers — les deux variantes tournent comme agents Kubernetes
dynamiques sur le même cluster, à la demande, sans node dédié par OS : c'est
la preuve concrète que Kubernetes résout le problème initial.

## Pipeline

Checkout → Checkov (lint Dockerfile) → Build image → Trivy (scan
vulnérabilités) → Syft (SBOM) → Build firmware (`make TARGET=x86`) →
SonarQube → Simulateur (validation ELF) → Push Harbor → Cosign (signature +
attestation SBOM). Détail complet des stages et des credentials :
`docs/apps-stack.md`.

## Où vit le code

- **Source de vérité** : `app/firmware-poc/` dans ce repo (GitHub).
- **GitLab** (`poc-ci/firmware-poc`) : simple miroir de démo, resynchronisé à
  la demande via `make gitlab-init` (`scripts/gitlab-init.sh`) — force-push
  d'un repo autonome à chaque appel, pas de lien d'historique avec GitHub.
  C'est GitLab qui déclenche Jenkins (webhook), pas GitHub.

## Dockerfile — arbitrages sécurité (Checkov)

Les deux Dockerfiles tournent en utilisateur non-root (UID 1000) et déclarent
un `HEALTHCHECK` minimal (vérifie que `gcc` reste utilisable) — corrige les 2
findings Checkov (`CKV_DOCKER_2`, `CKV_DOCKER_3`) détectés dès la première
exécution du pipeline. `/workspace` est en `chmod 1777` (comme `/tmp`) car
c'est un bind-mount du workspace Jenkins (créé par le checkout git, exécuté
en root côté conteneur `builder`) — sans ça, l'utilisateur non-root du
conteneur de build ne pourrait pas y écrire.
