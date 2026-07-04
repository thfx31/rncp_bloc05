# Fondation cluster (Phase 2) — GitOps, pas d'Ansible

Après un premier essai avec 6 rôles Ansible custom (un par brique, chacun
pilotant Helm), on est revenu à un modèle beaucoup plus plat, calqué sur ce qui
avait déjà fonctionné sur un précédent projet
([Ynov_k8s](https://github.com/thfx31/Ynov_k8s)) : **Ansible s'arrête après le
cluster RKE2 up** (Phase 1). Tout le reste est déclaratif, dans
`kubernetes/`, et pris en charge par ArgoCD lui-même dès son bootstrap.

## Pourquoi ce choix

Écrire un rôle Ansible par brique (avec meta-dépendances, wrapper autour de
`kubernetes.core.helm`, gestion de versions de charts dans des `defaults/`)
réinvente ce qu'ArgoCD sait déjà faire nativement (support Helm intégré, sync
waves pour l'ordre, self-heal). Ça ajoutait de la complexité sans valeur pour
un POC de démo 5 minutes — cf. `CONTEXT.md`. Un dossier de manifestes +
App-of-Apps est plus court, plus lisible, et plus proche de ce que fera
réellement tourner le cluster en continu (ArgoCD, pas Ansible).

## Arborescence

```
kubernetes/
  argocd-manager/
    root-app.yaml      # App-of-Apps racine
    00-infra.yaml       # Application "layer-00-infra" → kubernetes/00-infra/
  00-infra/
    local-path-provisioner.yaml       # Manifeste vendoré (upstream, tag v0.0.36) — StorageClass par défaut
    cilium-hubble.yaml                # HelmChartConfig rke2-cilium (active Hubble)
    scaleway-ccm.yaml                 # Manifeste vendoré (upstream, tag v0.36.1)
    ingress-nginx-app.yaml            # Application ArgoCD → chart Helm ingress-nginx
    cert-manager-app.yaml             # Application ArgoCD → chart Helm cert-manager
    cert-manager-webhook-ovh-app.yaml # Application ArgoCD → chart webhook OVH + ClusterIssuer prod/staging
    argocd-ingress.yaml               # Ingress pour argocd-server lui-même
```

**Ajouté après coup** : `local-path-provisioner` — RKE2 ne bundle aucun
provisioner de stockage par défaut dans cette configuration (découvert au
moment d'attaquer la Phase 3, cf. `docs/apps-stack.md`), alors que
`CONTEXT.md` supposait le contraire. Sans lui, aucun PVC ne peut se lier.

## Séquence de bootstrap (`make`)

```bash
make kubeconfig         # déjà fait en Phase 1
make k8s-secrets        # Secrets scaleway-secret + ovh-credentials (env vars, jamais commités)
make k8s-bootstrap-argocd  # kubectl apply du manifeste officiel ArgoCD (pas de Helm) + root-app
```

`make k8s-bootstrap-argocd` :
1. Applique le manifeste officiel ArgoCD (`argo-cd/stable/manifests/install.yaml`) — pas de chart Helm pour ArgoCD lui-même, un seul `kubectl apply`.
2. Patch `argocd-server` avec `--insecure` (TLS terminé par l'Ingress NGINX via cert-manager, pas par ArgoCD).
3. Applique `kubernetes/argocd-manager/root-app.yaml`.

À partir de là, **ArgoCD prend le relais tout seul** : `root-app` sync
`00-infra.yaml`, qui sync tout le contenu de `kubernetes/00-infra/` — CCM,
Hubble, ingress-nginx, cert-manager (+ webhook OVH + ClusterIssuer), et enfin
l'Ingress d'ArgoCD lui-même. L'ordre est garanti par les annotations
`argocd.argoproj.io/sync-wave` (0 → CCM/Hubble/ingress-nginx/cert-manager,
1 → webhook OVH, 2 → Ingress ArgoCD).

## Détail par brique

**scaleway-ccm** — Deployment/RBAC vendorés depuis le manifeste upstream (tag
`v0.36.1`, image pinnée au lieu de `:latest`). Nécessaire pour que
`ingress-nginx` (`service.type: LoadBalancer`) obtienne un vrai Load Balancer
Scaleway. Secret `scaleway-secret` créé hors Git par `make k8s-secrets`
(mêmes variables d'environnement que Terraform).

**cilium-hubble** — RKE2 gère Cilium nativement (`rke2_cni: cilium`, Phase 1) ;
ce `HelmChartConfig` active juste Hubble/Relay/UI dans le HelmChart déjà géré
par RKE2, sans réinstaller un second Cilium.

**ingress-nginx** — Application ArgoCD pointant directement sur le chart Helm
upstream (pas de vendoring). `service.type: LoadBalancer`,
`ingressClassResource.default: true`.

**cert-manager + webhook OVH** — deux Applications séparées (sync-wave 0 puis
1) car le webhook a besoin des CRDs/webhook cert-manager déjà en place. Le
chart webhook crée directement les `ClusterIssuer` `letsencrypt-prod` et
`letsencrypt-staging` (DNS-01, `yplank.fr` chez OVH). Secret
`ovh-credentials` créé hors Git par `make k8s-secrets`.

**argocd-ingress** — Ingress HTTPS pour `argocd.k8s.yplank.fr`, certificat
`letsencrypt-prod`. Nécessite `argocd-server --insecure` (patché au bootstrap)
pour que NGINX termine le TLS.

## Versions — à revérifier avant un rebuild

Toutes les versions ci-dessous étaient les dernières stables en juillet 2026 :
- ingress-nginx chart `4.15.1` — https://github.com/kubernetes/ingress-nginx/releases
- cert-manager chart `v1.20.3` — https://cert-manager.io/docs/release-notes/
- cert-manager-webhook-ovh chart `0.9.13` — https://github.com/aureq/cert-manager-webhook-ovh/releases
- scaleway-ccm `v0.36.1` — https://github.com/scaleway/scaleway-cloud-controller-manager/releases
- ArgoCD — `stable` channel (toujours la dernière version stable au moment du bootstrap)

## Repo public — accès ArgoCD

`rncp_bloc05` est un repo GitHub **public** (choix assumé : aucun secret n'y
est committé, credentials Scaleway/OVH toujours via variables d'environnement,
cf. `docs/setup-guide.md`). ArgoCD clone donc `root-app`/`00-infra` en HTTPS
anonyme, sans credential à enregistrer ni à recréer à chaque rebuild.
