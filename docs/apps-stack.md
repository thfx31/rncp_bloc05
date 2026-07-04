# Stack applicative (Phase 3) — Harbor, GitLab, SonarQube, Jenkins

Même modèle GitOps que la Phase 2 (`docs/cluster-foundation.md`) : une nouvelle
couche `kubernetes/01-apps/`, synchronisée par une nouvelle Application
`layer-01-apps` (sync-wave `1`, après `layer-00-infra`), elle-même déclarée
dans `kubernetes/argocd-manager/01-apps.yaml`.

Le pattern (charts Helm officiels + `nodeSelector` pour répartir la charge +
resources trimmées + storage dédié) reprend ce qui avait déjà fonctionné sur
l'ancien repo `infra-rncp/cloud/kubernetes/apps/` — adapté à ce cluster
(hostnames `rncp-bc05-worker-01/02`, storageClass `local-path`) et sans mots
de passe en clair commités (le repo est public, contrairement à l'ancien).

## Prérequis découvert en cours de route : local-path-provisioner

Aucun `StorageClass` n'existait sur le cluster — RKE2 ne bundle pas
`local-path-provisioner` par défaut dans cette configuration. Ajouté dans
`kubernetes/00-infra/local-path-provisioner.yaml` (manifeste vendoré depuis
rancher/local-path-provisioner, tag `v0.0.36`), marqué `StorageClass` par
défaut. Toutes les apps de cette phase l'utilisent.

## Répartition sur les 2 workers

Cluster à ressources limitées (2 workers, 4 vCPU / 12 Go chacun) — les 4 apps
sont réparties via `nodeSelector` pour ne pas toutes atterrir sur le même
node :
- **worker-01** : Harbor (registry, core), GitLab (webservice, sidekiq), agents Jenkins
- **worker-02** : SonarQube, Jenkins (controller)

## Secrets — `make k8s-apps-secrets`

Mots de passe générés aléatoirement, jamais committés, régénérés à chaque
rebuild (mêmes principes que `make k8s-secrets` en Phase 2) :

| App | Secret K8s | Mécanisme chart |
|---|---|---|
| Harbor | `harbor-admin-password` (ns `harbor`) | `existingSecretAdminPassword` + `existingSecretSecretKey` |
| GitLab | `gitlab-initial-root-password` (ns `gitlab`) | `global.initialRootPassword.secret` |
| Jenkins | `jenkins-admin-secret` (ns `jenkins`) | `controller.admin.existingSecret` |
| SonarQube | `sonarqube-secrets` (ns `sonarqube`) | `monitoringPasscodeSecretName` — passcode de probe, pas un mot de passe admin. Compte `admin/admin` par défaut, SonarQube force le changement au premier login |

```bash
make k8s-apps-secrets   # à lancer après make k8s-bootstrap-argocd, avant que layer-01-apps ne sync
```

Les mots de passe générés (Harbor, GitLab, Jenkins) sont affichés une seule
fois en sortie de commande — à noter pendant la session, ils ne sont
récupérables ensuite que via `kubectl get secret <nom> -o jsonpath=...` tant
que le cluster tourne.

## Détail par brique

**Harbor** — registry d'images, exposé `harbor.k8s.yplank.fr`. `updateStrategy:
Recreate` sur `registry`/`jobservice` (PVC RWO, un `RollingUpdate` bloquerait
sur un volume déjà monté).

**GitLab** — code C fictif. Beaucoup de sous-composants désactivés pour le
POC (`registry` propre à GitLab désactivé — Harbor le remplace ;
`gitlab-runner`, `prometheus`, `pages`, `kas` désactivés). `webservice`/
`sidekiq` figés à 1 replica.

**Chart figé en 9.x, pas 10.x** : depuis la version 10.0.0, le chart GitLab a
supprimé les sous-charts PostgreSQL/Redis embarqués — une base externe devient
obligatoire (`global.psql.host`/`global.redis.host`). Hors scope pour ce POC
(pas de valeur de démo à démontrer une base externe en plus). La branche 9.x
reçoit encore des mises à jour de sécurité sur l'image applicative (dernière :
`9.11.7` / GitLab `v18.11.6`), juste pas de nouvelles fonctionnalités de chart.

**SonarQube** — analyse statique du code C, déjà utilisé en prod chez le
client (cf. `CONTEXT.md`). Edition `community`.

**Jenkins** — controller + agents dynamiques (plugin `kubernetes`). Plugins
givrés au `latest` (pas de version pinnée comme les charts — acceptable pour
un plugin Jenkins, moins critique niveau reproductibilité qu'un chart/image).

## Versions — à revérifier avant un rebuild

- Harbor chart `1.19.1` — https://github.com/goharbor/harbor-helm/releases
- GitLab chart `9.11.7` (⚠️ pas 10.x) — https://gitlab.com/gitlab-org/charts/gitlab/-/releases
- SonarQube chart `2026.3.1` — https://github.com/SonarSource/helm-chart-sonarqube/releases
- Jenkins chart `5.9.32` — https://github.com/jenkinsci/helm-charts/releases
- local-path-provisioner `v0.0.36` — https://github.com/rancher/local-path-provisioner/releases

## Ordre de déploiement

`layer-01-apps` (sync-wave 1) vient après `layer-00-infra` (sync-wave 0) —
mais les 4 apps de cette couche n'ont pas de dépendance d'ordre entre elles
(pas de sync-wave interne), elles peuvent démarrer en parallèle. La seule
vraie dépendance est `local-path-provisioner` (Phase 2), sans quoi aucun PVC
ne peut se lier.
