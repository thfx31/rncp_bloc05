## Arborescence

```
kubernetes/
  argocd-manager/
    root-app.yaml                     # App-of-Apps racine
    00-infra.yaml                     # Application "layer-00-infra"
  00-infra/
    local-path-provisioner.yaml       # StorageClass par défaut
    cilium-hubble.yaml                # HelmChartConfig rke2-cilium (active Hubble)
    scaleway-ccm.yaml                 # Manifeste vendoré
    ingress-nginx-app.yaml            # Application ArgoCD (chart Helm ingress-nginx)
    cert-manager-app.yaml             # Application ArgoCD (chart Helm cert-manager)
    cert-manager-webhook-ovh-app.yaml # Application ArgoCD (chart webhook OVH + ClusterIssuer prod/staging)
    argocd-ingress.yaml               # Ingress pour argocd-server lui-même
```

## Séquence de bootstrap (`make`)

```bash
make kubeconfig            # Récupère le kubeconfig
make k8s-secrets           # Gère les Secrets scaleway-secret + ovh-credentials
make k8s-bootstrap-argocd  # kubectl apply du manifeste officiel ArgoCD (pas de Helm) + root-app
```

`make k8s-bootstrap-argocd` :
1. Applique le manifeste officiel ArgoCD (`argo-cd/stable/manifests/install.yaml`).
2. Patch `argocd-server` avec `--insecure` (TLS terminé par l'Ingress NGINX via cert-manager, pas par ArgoCD).
3. Applique `kubernetes/argocd-manager/root-app.yaml`.

À partir de là, **ArgoCD prend le relais tout seul** : `root-app` sync
`00-infra.yaml`, qui sync tout le contenu de `kubernetes/00-infra/` - CCM,
Hubble, ingress-nginx, cert-manager (+ webhook OVH + ClusterIssuer), et enfin
l'Ingress d'ArgoCD lui-même. L'ordre est garanti par les annotations
`argocd.argoproj.io/sync-wave` (0 → CCM/Hubble/ingress-nginx/cert-manager,
1 → webhook OVH, 2 → Ingress ArgoCD).

## Détail par brique

**scaleway-ccm** - Deployment/RBAC vendorés. Nécessaire pour que
`ingress-nginx` (`service.type: LoadBalancer`) obtienne un vrai Load Balancer
Scaleway. Secret `scaleway-secret` créé hors Git par `make k8s-secrets`.


**cilium-hubble** - RKE2 gère Cilium nativement (`rke2_cni: cilium`, Phase 1) ;
ce `HelmChartConfig` active juste Hubble/Relay/UI dans le HelmChart déjà géré
par RKE2, sans réinstaller un second Cilium.

**ingress-nginx** - Application ArgoCD pointant directement sur le chart Helm
upstream.

**cert-manager + webhook OVH** - deux Applications séparées (sync-wave 0 puis 1) 
car le webhook a besoin des CRDs/webhook cert-manager déjà en place. Le
chart webhook crée directement les `ClusterIssuer` `letsencrypt-prod` et
`letsencrypt-staging` (DNS-01, `yplank.fr` chez OVH). Secret
`ovh-credentials` créé hors Git par `make k8s-secrets`.

**argocd-ingress** - Ingress HTTPS pour `argocd.k8s.yplank.fr`, certificat
`letsencrypt-prod`. Nécessite `argocd-server --insecure` (patché au bootstrap)
pour que NGINX termine le TLS.

## Versions - à revérifier avant un rebuild

Toutes les versions ci-dessous étaient les dernières stables en juillet 2026 :
- ingress-nginx chart `4.15.1` - https://github.com/kubernetes/ingress-nginx/releases
- cert-manager chart `v1.20.3` - https://cert-manager.io/docs/release-notes/
- cert-manager-webhook-ovh chart `0.9.13` - https://github.com/aureq/cert-manager-webhook-ovh/releases
- scaleway-ccm `v0.36.1` - https://github.com/scaleway/scaleway-cloud-controller-manager/releases
- ArgoCD - `stable` channel (toujours la dernière version stable au moment du bootstrap)

## Repo public - accès ArgoCD

`rncp_bloc05` est un repo GitHub **public** (aucun secret n'y
est committé, credentials Scaleway/OVH toujours via variables d'environnement,
cf. `docs/setup.md`). ArgoCD clone donc `root-app`/`00-infra` en HTTPS
anonyme, sans credential à enregistrer ni à recréer à chaque rebuild.
