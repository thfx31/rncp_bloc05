# Stack applicative - Harbor, GitLab, SonarQube, Jenkins

C'est une couche `kubernetes/01-apps/`, synchronisée par une nouvelle Application
`layer-01-apps` (sync-wave `1`, après `layer-00-infra`), elle-même déclarée
dans `kubernetes/argocd-manager/01-apps.yaml`.

Le pattern (charts Helm officiels + `nodeSelector` pour répartir la charge +
resources trimmées + storage dédié), storageClass `local-path` et sans mots
de passe en clair commités.

## Prérequis : local-path-provisioner

RKE2 ne bundle pas `local-path-provisioner` par défaut dans cette configuration. Ajouté dans
`kubernetes/00-infra/local-path-provisioner.yaml` (manifeste vendoré depuis
rancher/local-path-provisioner, tag `v0.0.36`), marqué `StorageClass` par
défaut. Toutes les apps de cette phase l'utilisent.

## Répartition sur les 2 workers

Cluster à ressources limitées (2 workers, 4 vCPU / 12 Go chacun) - les 4 apps
sont réparties via `nodeSelector` pour ne pas toutes atterrir sur le même
node :
- **worker-01** : Harbor (registry, core), GitLab (webservice, sidekiq), agents Jenkins
- **worker-02** : SonarQube, Jenkins (controller)

## Secrets - `make k8s-apps-secrets`

Mots de passe générés aléatoirement, jamais committés, régénérés à chaque
rebuild (mêmes principes que `make k8s-secrets` en Phase 2) :

| App | Secret K8s |
|---|---|
| Harbor | `harbor-admin-password` (ns `harbor`) |
| GitLab | `gitlab-initial-root-password` (ns `gitlab`) |
| Jenkins | `jenkins-admin-secret` (ns `jenkins`) |
| SonarQube | `sonarqube-secrets` (ns `sonarqube`) |

```bash
make k8s-apps-secrets   # à lancer après make k8s-bootstrap-argocd, avant que layer-01-apps ne sync
```

Les mots de passe générés (Harbor, GitLab, Jenkins) sont affichés une seule
fois en sortie de commande. Si perdus, ils
restent récupérables tant que le cluster tourne :

```bash
# Harbor (login admin UI/registry)
kubectl get secret harbor-admin-password -n harbor -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 -d; echo

# GitLab (login root)
kubectl get secret gitlab-initial-root-password -n gitlab -o jsonpath='{.data.password}' | base64 -d; echo

# Jenkins (login admin)
kubectl get secret jenkins-admin-secret -n jenkins -o jsonpath='{.data.jenkins-admin-password}' | base64 -d; echo

# SonarQube - pas de secret admin à lire ici, login par défaut admin/admin (changement forcé au premier login)
kubectl get secret sonarqube-secrets -n sonarqube -o jsonpath='{.data.monitoringPasscode}' | base64 -d; echo
```

## Credentials Jenkins - `make jenkins-credentials`

Le pipeline Jenkinsfile (`app/firmware-poc/Jenkinsfile`) a besoin d'accéder à
Harbor, GitLab, SonarQube et de la clé Cosign. Plutôt que de créer ces
credentials à la main dans l'UI Jenkins,
le plugin `kubernetes-credentials-provider` (ajouté à `jenkins-app.yaml`)
synchronise automatiquement des Secrets Kubernetes labellisés vers le store
de credentials Jenkins :

| Credential Jenkins | Secret K8s (ns `jenkins`) | Source de la valeur |
|---|---|---|
| `harbor-credentials` | `harbor-credentials` (`kubernetes.io/basic-auth`) | copié depuis `harbor-admin-password` (ns `harbor`) |
| `gitlab-credentials` | `gitlab-credentials` (`kubernetes.io/basic-auth`) | copié depuis `gitlab-initial-root-password` (ns `gitlab`) |
| `cosign-private-key` | `cosign-private-key` (`secretText`) | copié depuis `~/.cosign/rncp-bc05/cosign.key` sur le poste opérateur (jamais dans le repo, cf. `docs/cosign.md`) |
| `sonarqube-token` | `sonarqube-token` (`secretText`, à créer manuellement) | token API généré une fois via l'UI SonarQube (`admin` → `My Account` → `Security` → `Generate Token`) |

```bash
make jenkins-credentials   # à lancer après make gitlab-init, idempotent (comme k8s-apps-secrets)
```

**Procédure manuelle - token SonarQube** (pas automatisable proprement : le
mot de passe `admin`/`admin` par défaut force un changement au premier
login) :

1. Ouvrir `https://sonarqube.k8s.yplank.fr/`, se connecter en `admin`/`admin`,
   changer le mot de passe quand demandé.
2. Avatar (haut droite) → **My Account** → onglet **Security**.
3. Section **Generate Tokens** : nom `jenkins`, type **Global Analysis
   Token** (scope restreint à la soumission de résultats d'analyse - pas un
   **User Token**, qui hériterait de tous les droits admin ; principe de
   moindre privilège, seul le résultat du scan doit pouvoir être poussé).
4. Copier le token affiché (visible une seule fois), puis :

```bash
kubectl create secret generic sonarqube-token -n jenkins --from-literal=text="<token>"
kubectl label secret sonarqube-token -n jenkins jenkins.io/credentials-type=secretText
kubectl annotate secret sonarqube-token -n jenkins jenkins.io/credentials-description="SonarQube token (manuel)"
```

RBAC dédiée (`kubernetes/01-apps/jenkins-secrets-rbac.yaml`) : un `Role` +
`RoleBinding` donnant au ServiceAccount `jenkins` le droit de lire les Secrets
de son propre namespace - nécessaire pour que le plugin puisse les découvrir.

## Job Jenkins + webhook GitLab

Le job pipeline `firmware-poc` est défini de façon déclarative. Le
déclenchement se fait par un **webhook GitLab → Jenkins** (`gitlab-plugin`),
sécurisé par un token partagé :

- `gitlab-webhook-token` (Secret K8s, ns `jenkins`, généré par
  `make jenkins-credentials`) - injecté dans le pod Jenkins comme variable
  d'env `GITLAB_WEBHOOK_TOKEN`, lue par le Job DSL (`secretToken(...)`).
- `scripts/gitlab-init.sh` lit ce même secret et configure le webhook côté
  GitLab (`POST/PUT /projects/:id/hooks`) pointant vers
  `https://jenkins.k8s.yplank.fr/project/firmware-poc`.

**Ordre obligatoire** (le token doit exister avant que le webhook puisse être
créé côté GitLab) :

```bash
make gitlab-init           # 1. crée groupe/projet + push (webhook skip, token pas encore là)
make jenkins-credentials   # 2. crée gitlab-webhook-token (+ harbor/gitlab/cosign credentials)
make gitlab-init           # 3. relancé - cette fois configure le webhook (idempotent, ne recrée rien d'autre)
```

## Détail par brique

**Harbor** - registry d'images, exposé `harbor.k8s.yplank.fr`.

**GitLab** - code C fictif. Beaucoup de sous-composants désactivés pour le
POC (`registry` propre à GitLab désactivé - Harbor le remplace ;
`gitlab-runner`, `prometheus`, `pages`, `kas` désactivés). `webservice`/
`sidekiq` figés à 1 replica.

**Chart figé en 9.x, pas 10.x** : depuis la version 10.0.0, le chart GitLab a
supprimé les sous-charts PostgreSQL/Redis embarqués - une base externe devient
obligatoire (`global.psql.host`/`global.redis.host`). Hors scope pour ce POC
(pas de valeur de démo à démontrer une base externe en plus).

**SonarQube** - analyse statique du code C, déjà utilisé en prod chez le
client (cf. `docs/architecture.md`). Edition `community`.

**Jenkins** - controller + agents dynamiques (plugin `kubernetes`).


## Ordre de déploiement

`layer-01-apps` (sync-wave 1) vient après `layer-00-infra` (sync-wave 0) -
mais les 4 apps de cette couche n'ont pas de dépendance d'ordre entre elles
(pas de sync-wave interne), elles peuvent démarrer en parallèle. La seule
vraie dépendance est `local-path-provisioner` (Phase 2), sans quoi aucun PVC
ne peut se lier.
