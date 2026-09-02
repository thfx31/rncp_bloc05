# Évolutions possibles (non implémentées)

Pistes identifiées et argumentées pendant le projet, écartées du périmètre de
ce POC par arbitrage risque/valeur (temps de démo de 5 minutes, briques déjà
suffisamment démontrées) - pas des oublis.

## Vault - auth Kubernetes native

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
(webhook GitLab↔Jenkins, résolution d'image Checkov) - pour une brique qui
n'est de toute façon pas montrée en démo.

## Jenkins ↔ Vault (lecture dynamique de secret)

Suite logique du point précédent : un stage Jenkinsfile qui va chercher un
secret via l'API HTTP Vault (login K8s-auth + lecture KV), plutôt qu'un
credential Jenkins statique. Approche simple envisagée : deux appels `curl`
directs (pas de plugin Jenkins Vault, pour éviter de dépendre d'un schéma de
configuration Groovy/JCasC peu documenté - cf. incident `secretToken()` sur le
Job DSL GitLab, similaire en risque). Non implémenté, dépend du point
précédent.

## ESO - External Secrets Operator

**Objectif envisagé** : démontrer un secret Vault synchronisé automatiquement
en Secret Kubernetes natif (`ClusterSecretStore` + `ExternalSecret`), sans
dépendre d'un script qui copie une valeur une seule fois.

**Pourquoi pas maintenant** : dépend de l'auth K8s Vault (ci-dessus), plus une
gestion TLS spécifique côté CRD (`caProvider`, pas toujours de mode
"skip verify" simple selon la version du CRD) - jamais testée sur ce cluster.

## Gitleaks (scan de secrets dans le code)

Abandonné dès le cadrage initial - pas de scan de secrets dans le code
applicatif retenu pour ce POC (le cas d'usage étant fictif, le risque de fuite
de secret réel dans le code n'existe pas dans ce périmètre).
