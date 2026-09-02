# Setup - mise en place et reconstruction complète

Mode opératoire à redérouler tel quel, que ce soit la toute première
mise en place ou une reconstruction après un destroy.

Chaque étape renvoie vers la doc détaillée correspondante si besoin de
contexte (`docs/vault.md`, `docs/cluster-foundation.md`) - ce runbook ne fait
que dérouler l'ordre et les commandes.

## Prérequis Scaleway (manuel, une seule fois)

Au premier run :

- [x] Compte Scaleway + projet dédié RNCP
- [x] Clé API IAM (`SCW_ACCESS_KEY` / `SCW_SECRET_KEY`) récupérée
- [x] `SCW_DEFAULT_PROJECT_ID` récupéré
- [x] `SCW_DEFAULT_ORGANIZATION_ID` récupéré
- [x] Clé SSH ajoutée au projet Scaleway (Console -> Project Settings -> SSH Keys)
- [x] Bucket Object Storage `terraform-state-rncp-bc05` créé (Console -> Object
      Storage -> Create Bucket, région `fr-par`, **privé**)
- [x] Policy IAM Object Storage attachée à la clé API


## 0. Variables d'environnement (à exporter dans le shell)

```bash
# Provider Scaleway (Terraform + CCM)
export SCW_ACCESS_KEY=...
export SCW_SECRET_KEY=...
export SCW_DEFAULT_PROJECT_ID=...
export SCW_DEFAULT_ORGANIZATION_ID=...

# Backend S3 Terraform (mêmes valeurs, noms attendus par le backend "s3")
export AWS_ACCESS_KEY_ID=$SCW_ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$SCW_SECRET_KEY

# cert-manager - DNS-01 OVH pour yplank.fr (application API dédiée, droits
# scopés sur /domain/zone/yplank.fr* uniquement - cf. docs/cluster-foundation.md)
export OVH_APPLICATION_KEY=...
export OVH_APPLICATION_SECRET=...
export OVH_CONSUMER_KEY=...
```

## 1. Terraform - cluster puis Vault

```bash
make tf-cluster-apply   # réseau privé, control-plane, workers
make tf-vault-apply     # VM Vault dédiée - après cluster (data source réseau par nom)
```

## 2. Ansible - RKE2 puis Vault

```bash
make ansible-k8s        # bootstrap OS + RKE2 control-plane/agents
make ansible-vault      # install Vault (TLS auto-signée, raft single-node)
```

**Alternative** : les étapes 1 et 2 ci-dessus sont automatisables
via le workflow GitHub Actions `infra-deploy`. Reprendre ensuite à
l'étape 3 ci-dessous.

## 3. Vault - init + unseal (manuel, à refaire à chaque recréation de la VM)

```bash
export VAULT_ADDR="https://<ip-publique-vault>:8200"
export VAULT_SKIP_VERIFY=true

vault operator init          # génère 5 unseal keys + 1 root token (nouveaux à chaque fois)
vault operator unseal        # x3, avec 3 clés différentes
vault status                 # doit afficher "Sealed: false"
```

Détail complet : `docs/vault.md`.

## 4. Récupérer le kubeconfig

```bash
make kubeconfig
export KUBECONFIG=~/.kube/config-rncp-bc05
make nodes    # vérifier que les 3 nodes sont Ready
```

## 5. Fondation cluster - Secrets, CCM, puis ArgoCD

```bash
make k8s-secrets           # Secrets scaleway-secret (kube-system) + ovh-credentials (cert-manager)
make k8s-ccm               # CCM Scaleway - lève le taint "uninitialized" sur les nodes
make k8s-bootstrap-argocd  # ArgoCD (manifeste officiel) + patch --insecure + root-app
```

À partir d'ici, ArgoCD prend le relais : `root-app` sync `layer-00-infra`, qui
déploie Hubble, ingress-nginx, cert-manager + webhook OVH + ClusterIssuer.
Détail : `docs/cluster-foundation.md`.

```bash
kubectl get application -n argocd   # attendre Synced/Healthy sur tout sauf root-app
```

## 6. DNS - wildcard *.k8s.yplank.fr

Récupérer l'IP du Load Balancer Scaleway provisionné par le CCM :

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx
```

Créer/mettre à jour **un seul enregistrement wildcard** chez OVH (zone
`yplank.fr`, manuel via la console OVH ou API) - couvre `argocd.k8s`,
`harbor.k8s`, `gitlab.k8s`, `sonarqube.k8s`, `jenkins.k8s` et tout sous-domaine
futur sans repasser par le DNS à chaque nouvelle app :

| Type | Sous-domaine | Cible |
|---|---|---|
| A | `*.k8s` | IP du LoadBalancer ci-dessus |

Vérifier la propagation et le certificat :

```bash
dig +short argocd.k8s.yplank.fr A
kubectl get certificate -n argocd     # argocd-tls doit passer READY: True
curl -sk -o /dev/null -w "HTTP %{http_code}\n" https://argocd.k8s.yplank.fr/
```

## 7. Récupérer le mot de passe admin ArgoCD

Affiché en sortie de `make k8s-bootstrap-argocd`, ou à défaut :

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

## 8. Observabilité - Prometheus/Grafana + Loki/Promtail

Détail complet : `docs/monitoring.md`.

```bash
make k8s-monitoring-secrets   # Secret admin Grafana (généré, affiché une fois)
```

`layer-02-observability` (sync-wave 2) prend le relais tout seul ensuite.
Rien à ajouter côté DNS - le wildcard `*.k8s.yplank.fr` (étape 6) couvre déjà
`grafana.k8s.yplank.fr`.

```bash
kubectl get application -n argocd   # attendre Synced/Healthy sur kube-prometheus-stack/loki-stack
```

## 9. Stack applicative - Harbor, GitLab, SonarQube, Jenkins

Détail complet : `docs/apps-stack.md`.

```bash
make k8s-apps-secrets   # Secrets admin Harbor/GitLab/Jenkins (générés, affichés une fois) + SonarQube passcode
```

`layer-01-apps` (sync-wave 1, après `layer-00-infra`) prend le relais tout
seul dès que le commit est poussé - pas de commande supplémentaire.

```bash
kubectl get application -n argocd   # attendre Synced/Healthy sur harbor/gitlab/sonarqube/jenkins
```

Mots de passe (générés une seule fois, affichés en sortie de
`make k8s-apps-secrets` - si perdus, récupérables tant que le cluster tourne,
détail complet des 4 apps dans `docs/apps-stack.md`) :

```bash
# GitLab (login root)
kubectl get secret gitlab-initial-root-password -n gitlab -o jsonpath='{.data.password}' | base64 -d; echo
```

## 10. Pipeline sécurisé - firmware-poc

Détail complet : `docs/apps-stack.md` (credentials/webhook) et
`docs/cosign.md` (clé de signature).

```bash
# 1. Clé Cosign (une seule fois, réutilisable entre rebuilds - ~/.cosign/rncp-bc05/)
COSIGN_PASSWORD="" cosign generate-key-pair   # si ~/.cosign/rncp-bc05/cosign.key absent

# 2. Projet Harbor "poc-ci"
make harbor-init

# 3. Bootstrap GitLab (groupe/projet + push du code)
make gitlab-init

# 4. Credentials Jenkins (Harbor/GitLab/Cosign + token webhook)
make jenkins-credentials

# 5. Relancer gitlab-init - configure le webhook GitLab -> Jenkins
make gitlab-init

# 6. Étape manuelle : générer un token SonarQube (admin/admin, changement de
#    mot de passe forcé au 1er login) puis :
kubectl create secret generic sonarqube-token -n jenkins --from-literal=text="<token>"
kubectl label secret sonarqube-token -n jenkins jenkins.io/credentials-type=secretText
```

**Étape manuelle supplémentaire - plugin C/C++ SonarQube** : sans elle, le
stage "SonarQube analysis" tourne mais remonte 0 ligne de code (Community
Edition ne supporte pas nativement le C). Procédure complète (téléchargement
du plugin, redémarrage du pod, profil qualité CXX, Quality Gate) :
`docs/sonarqube-cxx-plugin.md` - à rejouer avant le premier build du pipeline
`firmware-poc`.

**Premier build** : le job `firmware-poc` est créé automatiquement (Job DSL,
au démarrage de Jenkins) mais Jenkins n'affiche **Build with Parameters**
(paramètre `VARIANT: legacy|modern`) qu'après avoir exécuté le Jenkinsfile
au moins une fois - lancer un premier `Build Now` (tourne avec les valeurs
par défaut), puis rafraîchir la page du job.

Le webhook GitLab déclenche automatiquement `VARIANT=legacy` à chaque push
sur le projet `firmware-poc`. `VARIANT=modern` (Ubuntu 22.04/gcc-12) se
lance uniquement à la main via **Build with Parameters** - démontre que les
deux OS tournent comme agents Kubernetes dynamiques sur le même cluster,
sans node Jenkins dédié par OS (cf. `docs/architecture.md`, problématique de départ).


## 11. Nettoyage en fin de session (destroy)

```bash
make tf-vault-destroy
make tf-cluster-destroy
```

**Alternative** : workflow GitHub Actions `infra-destroy` (avec `confirm: "destroy"`).

Rien d'autre à nettoyer : pas de state local persistant en dehors de
Terraform (backend S3) et du LB.
