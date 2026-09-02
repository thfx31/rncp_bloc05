# firmware-poc - cas d'usage applicatif (Phase 4/6)

Un firmware fictif pour un sous-système satellite ciblant ARM Cortex-M avec un code C minimal
(`app/firmware-poc/src/`), plus un "simulateur" (`simulator/simulator.c`) qui
valide le binaire produit (format ELF, taille, section exécutable) en guise
de test d'intégration sans matériel réel.

## Pourquoi un cas fictif

Le contexte réel, support à des développeurs de logiciel embarqué C, ne
peut pas être démontré avec du vrai code ou de vrais outils. Ce cas d'usage reproduit le problème réel sans
exposer quoi que ce soit de sensible.

## Pipeline

Checkout > Checkov (lint Dockerfile) > Build image > Trivy (scan
vulnérabilités) > Syft (SBOM) > Build firmware (`make TARGET=x86`) >
SonarQube > Simulateur (validation ELF) > Push Harbor > Cosign (signature +
attestation SBOM). Détail complet des stages et des credentials :
`docs/apps-stack.md`.

## Où est le code

- **Source de vérité** : `app/firmware-poc/` dans ce repo (GitHub).
- **GitLab** (`poc-ci/firmware-poc`) : simple miroir de démo, resynchronisé à
  la demande via `make gitlab-init` (`scripts/gitlab-init.sh`).
  C'est GitLab qui déclenche Jenkins, pas GitHub.

## Dockerfile - arbitrages sécurité (Checkov)

Les deux Dockerfiles tournent en utilisateur non-root (UID 1000) et déclarent
un `HEALTHCHECK` minimal (vérifie que `gcc` reste utilisable) - corrige les 2
findings Checkov (`CKV_DOCKER_2`, `CKV_DOCKER_3`) détectés dès la première
exécution du pipeline. `/workspace` est en `chmod 1777` (comme `/tmp`) car
c'est un bind-mount du workspace Jenkins (créé par le checkout git, exécuté
en root côté conteneur `builder`) - sans ça, l'utilisateur non-root du
conteneur de build ne pourrait pas y écrire.

## `VARIANT=broken` - fixture de démo (recette DevSecOps)

Troisième choix du paramètre `VARIANT`, en plus de `legacy`/`modern` :
`docker/Dockerfile.broken` reprend `Dockerfile.legacy` **sans** les 2
corrections Checkov ci-dessus (pas de `USER` non-root, pas de `HEALTHCHECK`).
Sert uniquement à démontrer en direct que le 
pipeline bloque bien avant tout build/push dès qu'un Dockerfile est non
conforme.
