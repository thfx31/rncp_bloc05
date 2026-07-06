# Évolutions possibles (non implémentées)

Pistes identifiées et argumentées pendant le projet, écartées du périmètre de
ce POC par arbitrage risque/valeur (temps de démo de 5 minutes, briques déjà
suffisamment démontrées) — pas des oublis. Détail des décisions au moment où
elles ont été prises : `docs/poc-vs-prod.md`.

## Vault — auth Kubernetes native

**Aujourd'hui** : Vault (VM externe) contient des secrets KV gérés
manuellement ; Jenkins utilise des Secrets Kubernetes statiques
(`make jenkins-credentials`), copiés depuis les mots de passe générés ailleurs.

**Évolution envisagée** : activer la méthode d'auth `kubernetes` de Vault,
avec un rôle dédié par consommateur (least privilege). Jenkins (ou tout
workload) s'authentifierait dynamiquement via son ServiceAccount (JWT projeté)
plutôt que de recevoir un secret statique copié.

**Pourquoi pas maintenant** : nécessite une RBAC dédiée (ServiceAccount +
`ClusterRoleBinding system:auth-delegator` + un Secret de token long-lived,
mécanisme différent sur les versions récentes de Kubernetes), une reachability
réseau privé Vault↔API Kubernetes jamais validée sur ce cluster, et l'IP du
control-plane changeant à chaque rebuild (à résoudre dynamiquement). Risque de
debug comparable à des incidents déjà rencontrés sur des briques annexes
(webhook GitLab↔Jenkins, résolution d'image Checkov) — pour une brique qui
n'est de toute façon pas montrée en démo.

## Jenkins ↔ Vault (lecture dynamique de secret)

Suite logique du point précédent : un stage Jenkinsfile qui va chercher un
secret via l'API HTTP Vault (login K8s-auth + lecture KV), plutôt qu'un
credential Jenkins statique. Approche simple envisagée : deux appels `curl`
directs (pas de plugin Jenkins Vault, pour éviter de dépendre d'un schéma de
configuration Groovy/JCasC peu documenté — cf. incident `secretToken()` sur le
Job DSL GitLab, similaire en risque). Non implémenté, dépend du point
précédent.

## ESO — External Secrets Operator

**Objectif envisagé** : démontrer un secret Vault synchronisé automatiquement
en Secret Kubernetes natif (`ClusterSecretStore` + `ExternalSecret`), sans
dépendre d'un script qui copie une valeur une seule fois.

**Pourquoi pas maintenant** : dépend de l'auth K8s Vault (ci-dessus), plus une
gestion TLS spécifique côté CRD (`caProvider`, pas toujours de mode
"skip verify" simple selon la version du CRD) — jamais testée sur ce cluster.

## Kyverno — admission control

**Objectif envisagé** : `ClusterPolicy verifyImages` qui vérifie la signature
Cosign des images à l'admission — bloque un `kubectl apply` manuel qui
contournerait le pipeline (Cosign sécurise la sortie du pipeline, Kyverno
sécuriserait l'entrée du cluster — defense in depth).

**Pourquoi pas maintenant** : le firmware produit par le pipeline
(`app/firmware-poc/`) est un binaire ARM compilé, pas un workload Kubernetes —
la démo de Kyverno nécessiterait un déploiement artificiel (`kubectl run`
manuel sur l'image Harbor, hors pipeline) plutôt qu'un vrai maillon CD. Compte
tenu du temps de soutenance (30 min présentation + 15 min Q&A, dont le POC
n'est qu'une partie), le risque d'implémentation (scope `imageReferences` mal
calibré pouvant bloquer tout le cluster) n'était pas justifié pour une brique
qui ne rentrerait probablement pas dans le créneau de démo live.

**Mise en œuvre si repris** : chart `kyverno/kyverno`, policy avec
`validationFailureAction: Audit` d'abord (test avant bascule `Enforce`),
`exclude` des namespaces système, `imageReferences` scopé strictement à
`harbor.k8s.yplank.fr/*` pour ne pas tenter de vérifier les images tierces
(Harbor, Jenkins, ArgoCD eux-mêmes, jamais signées par ce pipeline).

## Workflows GitHub Actions deploy/destroy (infra)

**Objectif envisagé** (cf. plan initial) : `deploy-cluster.yml`,
`destroy-cluster.yml`, `deploy-vault.yml`, `destroy-vault.yml` en
`workflow_dispatch`, avec un GitHub Environment à approbation manuelle pour
les destroy — reconstruire/détruire l'infra en un clic depuis GitHub plutôt
que via `make`/Terraform en local.

**Pourquoi pas maintenant** : le code (Terraform/Ansible) n'évoluera plus
d'ici la soutenance — pas de valeur à automatiser un cycle de vie qui ne sera
plus rejoué que localement. `docs/rebuild-runbook.md` couvre déjà la procédure
manuelle complète. Aurait aussi nécessité de stocker des credentials cloud
avec pouvoir de destruction dans les Secrets d'un repo public — accepté comme
risque à éviter pour un gain qui ne sera pas utilisé.

## Gitleaks (scan de secrets dans le code)

Abandonné dès le cadrage initial — pas de scan de secrets dans le code
applicatif retenu pour ce POC (le cas d'usage étant fictif, le risque de fuite
de secret réel dans le code n'existe pas dans ce périmètre).
