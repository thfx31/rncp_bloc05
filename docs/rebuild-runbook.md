# Runbook — reconstruction complète de zéro

Mode opératoire linéaire à redérouler tel quel à chaque fois que l'infra est
détruite puis recréée (coût Scaleway entre deux sessions de travail). Distinct
de `docs/runbook-demo.md` (script des 5 minutes de démo, Phase 6/7) : ici,
c'est la remise en route technique, pas la présentation devant le jury.

Chaque étape renvoie vers la doc détaillée correspondante si besoin de
contexte (`docs/vault.md`, `docs/cluster-foundation.md`,
`docs/poc-vs-prod.md`) — ce runbook ne fait que dérouler l'ordre et les
commandes.

## 0. Variables d'environnement (à exporter dans le shell avant tout)

```bash
# Provider Scaleway (Terraform + CCM)
export SCW_ACCESS_KEY=...
export SCW_SECRET_KEY=...
export SCW_DEFAULT_PROJECT_ID=...
export SCW_DEFAULT_ORGANIZATION_ID=...

# Backend S3 Terraform (mêmes valeurs, noms attendus par le backend "s3")
export AWS_ACCESS_KEY_ID=$SCW_ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$SCW_SECRET_KEY

# cert-manager — DNS-01 OVH pour yplank.fr (application API dédiée, droits
# scopés sur /domain/zone/yplank.fr* uniquement — cf. docs/cluster-foundation.md)
export OVH_APPLICATION_KEY=...
export OVH_APPLICATION_SECRET=...
export OVH_CONSUMER_KEY=...
```

## 1. Terraform — cluster puis Vault

```bash
make tf-cluster-apply   # réseau privé, control-plane, workers
make tf-vault-apply     # VM Vault dédiée — après cluster (data source réseau par nom)
```

## 2. Ansible — RKE2 puis Vault

```bash
make ansible-k8s        # bootstrap OS + RKE2 control-plane/agents
make ansible-vault      # install Vault (TLS auto-signée, raft single-node)
```

## 3. Vault — init + unseal (manuel, à refaire à chaque recréation de la VM)

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

## 5. Fondation cluster — Secrets, CCM, puis ArgoCD

```bash
make k8s-secrets           # Secrets scaleway-secret (kube-system) + ovh-credentials (cert-manager)
make k8s-ccm               # CCM Scaleway — lève le taint "uninitialized" sur les nodes
make k8s-bootstrap-argocd  # ArgoCD (manifeste officiel) + patch --insecure + root-app
```

**Piège connu** : sans `make k8s-ccm` avant le bootstrap ArgoCD, RKE2
(`cloud-provider-name: external`) laisse le taint
`node.cloudprovider.kubernetes.io/uninitialized` sur tous les nodes — ArgoCD
(et tout le reste) reste `Pending` indéfiniment tant que le CCM n'a pas
tourné. Le Makefile encode déjà cet ordre (`k8s-bootstrap-argocd: k8s-ccm`).

À partir d'ici, ArgoCD prend le relais : `root-app` sync `layer-00-infra`, qui
déploie Hubble, ingress-nginx, cert-manager + webhook OVH + ClusterIssuer.
Détail : `docs/cluster-foundation.md`.

```bash
kubectl get application -n argocd   # attendre Synced/Healthy sur tout sauf root-app
                                     # (root-app reste OutOfSync — cosmétique, sans impact)
```

## 6. DNS — wildcard *.k8s.yplank.fr

Récupérer l'IP du Load Balancer Scaleway provisionné par le CCM :

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx
```

Créer/mettre à jour **un seul enregistrement wildcard** chez OVH (zone
`yplank.fr`, manuel via la console OVH ou API) — couvre `argocd.k8s`,
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

## 8. Stack applicative (Phase 3) — Harbor, GitLab, SonarQube, Jenkins

Détail complet : `docs/apps-stack.md`.

```bash
make k8s-apps-secrets   # Secrets admin Harbor/GitLab/Jenkins (générés, affichés une fois) + SonarQube passcode
```

`layer-01-apps` (sync-wave 1, après `layer-00-infra`) prend le relais tout
seul dès que le commit est poussé — pas de commande supplémentaire.

```bash
kubectl get application -n argocd   # attendre Synced/Healthy sur harbor/gitlab/sonarqube/jenkins
```

Rien à ajouter côté DNS — le wildcard `*.k8s.yplank.fr` (étape 6) couvre déjà
ces 4 sous-domaines.

## 9. Nettoyage en fin de session (destroy)

```bash
make tf-vault-destroy
make tf-cluster-destroy
```

Rien d'autre à nettoyer : pas de state local persistant en dehors de
Terraform (backend S3), le kubeconfig local et le mot de passe ArgoCD
deviennent obsolètes au prochain rebuild.
