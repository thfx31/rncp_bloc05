# ──────────────────────────────────────────────────────────
# Makefile — rncp-bc05
# Pilotage Terraform (cluster/vault) & Ansible depuis la machine de dev
# ──────────────────────────────────────────────────────────

SHELL := /bin/bash

ANSIBLE_DIR      := ansible
TF_CLUSTER_DIR   := terraform/cluster
TF_VAULT_DIR     := terraform/vault
KUBECONFIG_FILE  := $(HOME)/.kube/config-rncp-bc05
SSH_KEY          := ~/.ssh/id_ed25519-scw
COSIGN_KEY_FILE  := $(HOME)/.cosign/rncp-bc05/cosign.key

# ══════════════════════════════════════════════════════════
#  TERRAFORM — cluster
# ══════════════════════════════════════════════════════════

.PHONY: tf-cluster-init tf-cluster-plan tf-cluster-apply tf-cluster-destroy tf-cluster-output

## Initialiser Terraform (cluster)
tf-cluster-init:
	cd $(TF_CLUSTER_DIR) && terraform init

## Planifier les changements (cluster)
tf-cluster-plan:
	cd $(TF_CLUSTER_DIR) && terraform plan

## Appliquer les changements (cluster)
tf-cluster-apply:
	cd $(TF_CLUSTER_DIR) && terraform apply

## Détruire l'infra cluster
tf-cluster-destroy:
	cd $(TF_CLUSTER_DIR) && terraform destroy

## Afficher les outputs (cluster)
tf-cluster-output:
	cd $(TF_CLUSTER_DIR) && terraform output

# ══════════════════════════════════════════════════════════
#  TERRAFORM — vault
# ══════════════════════════════════════════════════════════

.PHONY: tf-vault-init tf-vault-plan tf-vault-apply tf-vault-destroy tf-vault-output

## Initialiser Terraform (vault) — doit venir après tf-cluster-apply
tf-vault-init:
	cd $(TF_VAULT_DIR) && terraform init

## Planifier les changements (vault)
tf-vault-plan:
	cd $(TF_VAULT_DIR) && terraform plan

## Appliquer les changements (vault)
tf-vault-apply:
	cd $(TF_VAULT_DIR) && terraform apply

## Détruire la VM Vault
tf-vault-destroy:
	cd $(TF_VAULT_DIR) && terraform destroy

## Afficher les outputs (vault)
tf-vault-output:
	cd $(TF_VAULT_DIR) && terraform output

# ══════════════════════════════════════════════════════════
#  ANSIBLE
# ══════════════════════════════════════════════════════════

.PHONY: ansible-inventory ansible-inventory-vault ping ansible-k8s ansible-vault

## Régénérer tf_outputs.json à partir des outputs Terraform du cluster
ansible-inventory:
	terraform -chdir=$(TF_CLUSTER_DIR) output -json > $(ANSIBLE_DIR)/tf_outputs.json

## Régénérer tf_outputs_vault.json à partir des outputs Terraform de vault
ansible-inventory-vault:
	terraform -chdir=$(TF_VAULT_DIR) output -json > $(ANSIBLE_DIR)/tf_outputs_vault.json

## Tester la connectivité SSH vers les nodes du cluster
ping: ansible-inventory
	cd $(ANSIBLE_DIR) && ansible k8s_cluster -m ping

## Bootstrap complet K8s/RKE2 (OS + control-plane + agents)
ansible-k8s: ansible-inventory
	cd $(ANSIBLE_DIR) && ansible-playbook bootstrap-k8s.yml

## Bootstrap complet Vault (install + config raft + TLS, sans init/unseal)
ansible-vault: ansible-inventory ansible-inventory-vault
	cd $(ANSIBLE_DIR) && ansible-playbook bootstrap-vault.yml

# ══════════════════════════════════════════════════════════
#  KUBERNETES — fondation cluster (GitOps, pas d'Ansible)
# ══════════════════════════════════════════════════════════

.PHONY: kubeconfig nodes k8s-secrets k8s-ccm k8s-bootstrap-argocd k8s-apps-secrets k8s-monitoring-secrets gitlab-init harbor-init jenkins-credentials

## Récupérer le kubeconfig depuis le control-plane
kubeconfig:
	@mkdir -p $(HOME)/.kube
	$(eval CP_IP := $(shell terraform -chdir=$(TF_CLUSTER_DIR) output -raw control_plane_ip_public))
	scp -i $(SSH_KEY) almalinux@$(CP_IP):.kube/config $(KUBECONFIG_FILE)
	@echo "Kubeconfig récupéré dans $(KUBECONFIG_FILE)"
	@echo "   export KUBECONFIG=$(KUBECONFIG_FILE)"

## Lister les nodes du cluster
nodes:
	KUBECONFIG=$(KUBECONFIG_FILE) kubectl get nodes -o wide

## Créer les Secrets requis par la fondation cluster (Scaleway CCM, OVH DNS-01)
## Lues depuis les mêmes variables d'environnement que Terraform + OVH_* (voir docs/setup-guide.md)
k8s-secrets:
	KUBECONFIG=$(KUBECONFIG_FILE) kubectl create secret generic scaleway-secret \
		-n kube-system \
		--from-literal=SCW_ACCESS_KEY="$$SCW_ACCESS_KEY" \
		--from-literal=SCW_SECRET_KEY="$$SCW_SECRET_KEY" \
		--from-literal=SCW_DEFAULT_PROJECT_ID="$$SCW_DEFAULT_PROJECT_ID" \
		--from-literal=SCW_DEFAULT_REGION="$${SCW_DEFAULT_REGION:-fr-par}" \
		--from-literal=SCW_DEFAULT_ZONE="$${SCW_DEFAULT_ZONE:-fr-par-2}" \
		--dry-run=client -o yaml | KUBECONFIG=$(KUBECONFIG_FILE) kubectl apply -f -
	KUBECONFIG=$(KUBECONFIG_FILE) kubectl create namespace cert-manager --dry-run=client -o yaml | KUBECONFIG=$(KUBECONFIG_FILE) kubectl apply -f -
	KUBECONFIG=$(KUBECONFIG_FILE) kubectl create secret generic ovh-credentials \
		-n cert-manager \
		--from-literal=applicationKey="$$OVH_APPLICATION_KEY" \
		--from-literal=applicationSecret="$$OVH_APPLICATION_SECRET" \
		--from-literal=applicationConsumerKey="$$OVH_CONSUMER_KEY" \
		--dry-run=client -o yaml | KUBECONFIG=$(KUBECONFIG_FILE) kubectl apply -f -

## Créer les Secrets admin de la stack applicative (Harbor, GitLab, SonarQube,
## Jenkins) — mots de passe générés aléatoirement, jamais committés.
## IDEMPOTENT : ne touche jamais un secret déjà présent (kubectl create, pas
## d'apply/overwrite). GitLab et Harbor ne lisent ce mot de passe qu'une seule
## fois, à leur tout premier bootstrap (migration DB) — le regénérer après
## coup désynchronise le secret de la vraie valeur en base, sans erreur
## visible avant un login qui échoue. Donc relancer cette cible à tout moment
## (ex. après un `kubectl delete secret` volontaire, ou pour compléter des
## secrets manquants) ne casse plus rien : seuls les secrets absents sont créés.
k8s-apps-secrets:
	@for ns in harbor gitlab sonarqube jenkins; do \
		KUBECONFIG=$(KUBECONFIG_FILE) kubectl create namespace $$ns --dry-run=client -o yaml | KUBECONFIG=$(KUBECONFIG_FILE) kubectl apply -f - ; \
	done
	@KUBECONFIG=$(KUBECONFIG_FILE) kubectl get secret harbor-admin-password -n harbor >/dev/null 2>&1 && \
		echo "harbor-admin-password existe déjà — inchangé" || \
		{ HARBOR_PW=$$(openssl rand -base64 24 | tr -d '=+/\n' | cut -c1-24); \
		  HARBOR_SECRETKEY=$$(openssl rand -base64 24 | tr -d '=+/\n' | cut -c1-16); \
		  KUBECONFIG=$(KUBECONFIG_FILE) kubectl create secret generic harbor-admin-password -n harbor \
			--from-literal=HARBOR_ADMIN_PASSWORD="$$HARBOR_PW" \
			--from-literal=secretKey="$$HARBOR_SECRETKEY"; \
		  echo "Harbor (admin)   : $$HARBOR_PW"; }
	@KUBECONFIG=$(KUBECONFIG_FILE) kubectl get secret gitlab-initial-root-password -n gitlab >/dev/null 2>&1 && \
		echo "gitlab-initial-root-password existe déjà — inchangé" || \
		{ GITLAB_PW=$$(openssl rand -base64 24 | tr -d '=+/\n' | cut -c1-24); \
		  KUBECONFIG=$(KUBECONFIG_FILE) kubectl create secret generic gitlab-initial-root-password -n gitlab \
			--from-literal=password="$$GITLAB_PW"; \
		  echo "GitLab (root)    : $$GITLAB_PW"; }
	@KUBECONFIG=$(KUBECONFIG_FILE) kubectl get secret sonarqube-secrets -n sonarqube >/dev/null 2>&1 && \
		echo "sonarqube-secrets existe déjà — inchangé" || \
		{ SONARQUBE_PASSCODE=$$(openssl rand -base64 24 | tr -d '=+/\n' | cut -c1-24); \
		  KUBECONFIG=$(KUBECONFIG_FILE) kubectl create secret generic sonarqube-secrets -n sonarqube \
			--from-literal=monitoringPasscode="$$SONARQUBE_PASSCODE"; \
		  echo "SonarQube        : admin/admin (changement forcé au 1er login)"; }
	@KUBECONFIG=$(KUBECONFIG_FILE) kubectl get secret jenkins-admin-secret -n jenkins >/dev/null 2>&1 && \
		echo "jenkins-admin-secret existe déjà — inchangé" || \
		{ JENKINS_PW=$$(openssl rand -base64 24 | tr -d '=+/\n' | cut -c1-24); \
		  KUBECONFIG=$(KUBECONFIG_FILE) kubectl create secret generic jenkins-admin-secret -n jenkins \
			--from-literal=jenkins-admin-user="admin" \
			--from-literal=jenkins-admin-password="$$JENKINS_PW"; \
		  echo "Jenkins (admin)  : $$JENKINS_PW"; }
	@echo ""
	@echo "Mots de passe (générés ci-dessus, ou déjà en place) — jamais committés."
	@echo "Pour forcer une rotation volontaire d'un secret : kubectl delete secret <nom> -n <ns>"
	@echo "puis relancer 'make k8s-apps-secrets' (et resynchroniser l'app côté GitLab/Harbor si"
	@echo "elle a déjà consommé l'ancien, cf. docs/apps-stack.md § dépannage)."

## Créer le Secret admin Grafana (Phase 5 — observabilité). IDEMPOTENT, même
## pattern que k8s-apps-secrets.
k8s-monitoring-secrets:
	@KUBECONFIG=$(KUBECONFIG_FILE) kubectl create namespace monitoring --dry-run=client -o yaml | KUBECONFIG=$(KUBECONFIG_FILE) kubectl apply -f -
	@KUBECONFIG=$(KUBECONFIG_FILE) kubectl get secret grafana-admin-secret -n monitoring >/dev/null 2>&1 && \
		echo "grafana-admin-secret existe déjà — inchangé" || \
		{ GRAFANA_PW=$$(openssl rand -base64 24 | tr -d '=+/\n' | cut -c1-24); \
		  KUBECONFIG=$(KUBECONFIG_FILE) kubectl create secret generic grafana-admin-secret -n monitoring \
			--from-literal=admin-user="admin" \
			--from-literal=admin-password="$$GRAFANA_PW"; \
		  echo "Grafana (admin)  : $$GRAFANA_PW"; }

## Déployer le CCM Scaleway — OBLIGATOIRE avant ArgoCD. RKE2 (cloud-provider-name:
## external) tainte tous les nodes node.cloudprovider.kubernetes.io/uninitialized
## tant qu'aucun CCM n'a tourné ; seul le CCM tolère ce taint, tout le reste
## (y compris ArgoCD) reste Pending tant qu'il n'a pas été levé.
k8s-ccm: k8s-secrets
	KUBECONFIG=$(KUBECONFIG_FILE) kubectl apply -f kubernetes/00-infra/scaleway-ccm.yaml
	KUBECONFIG=$(KUBECONFIG_FILE) kubectl wait --for=condition=available --timeout=300s deployment/scaleway-cloud-controller-manager -n kube-system

## Bootstrap ArgoCD (manifeste officiel, pas de Helm) + App-of-Apps
## --insecure : argocd-server sert en HTTP interne, TLS terminé par l'Ingress
## NGINX via cert-manager (cf. kubernetes/00-infra/argocd-ingress.yaml)
k8s-bootstrap-argocd: k8s-ccm
	KUBECONFIG=$(KUBECONFIG_FILE) kubectl create namespace argocd --dry-run=client -o yaml | KUBECONFIG=$(KUBECONFIG_FILE) kubectl apply -f -
	# --server-side : la CRD applicationsets.argoproj.io dépasse la limite de 256 Ko
	# de l'annotation kubectl.kubernetes.io/last-applied-configuration en apply client-side
	KUBECONFIG=$(KUBECONFIG_FILE) kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	KUBECONFIG=$(KUBECONFIG_FILE) kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
	KUBECONFIG=$(KUBECONFIG_FILE) kubectl patch deployment argocd-server -n argocd --type=json \
		-p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--insecure"}]'
	KUBECONFIG=$(KUBECONFIG_FILE) kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
	KUBECONFIG=$(KUBECONFIG_FILE) kubectl apply -f kubernetes/argocd-manager/root-app.yaml
	@echo "ArgoCD admin password :"
	@KUBECONFIG=$(KUBECONFIG_FILE) kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo

## Bootstrap du projet GitLab firmware-poc (Phase 4/6) — crée le groupe/projet
## via l'API GitLab (idempotent) et pousse app/firmware-poc/ (source de vérité
## sur GitHub) comme repo autonome. À lancer une fois que GitLab est Healthy
## (make k8s-apps-secrets déjà exécuté). Voir scripts/gitlab-init.sh.
gitlab-init:
	KUBECONFIG=$(KUBECONFIG_FILE) ./scripts/gitlab-init.sh

## Créer le projet Harbor "poc-ci" (idempotent) — sans ça, un docker push
## échoue avec "unauthorized: project poc-ci not found". Harbor ne crée que
## le projet "library" par défaut.
harbor-init:
	@HARBOR_PW=$$(KUBECONFIG=$(KUBECONFIG_FILE) kubectl get secret harbor-admin-password -n harbor -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 -d); \
	EXISTS=$$(curl -sk -u "admin:$$HARBOR_PW" https://harbor.k8s.yplank.fr/api/v2.0/projects/poc-ci -o /dev/null -w '%{http_code}'); \
	if [ "$$EXISTS" = "200" ]; then \
		echo "Projet Harbor poc-ci existe déjà — inchangé"; \
	else \
		curl -sk -u "admin:$$HARBOR_PW" -X POST https://harbor.k8s.yplank.fr/api/v2.0/projects \
			-H "Content-Type: application/json" \
			-d '{"project_name":"poc-ci","public":false}'; \
		echo "Projet Harbor poc-ci créé"; \
	fi

## Credentials Jenkins (Harbor, GitLab, Cosign) via kubernetes-credentials-provider
## — Secrets K8s labellisés jenkins.io/credentials-type, découverts automatiquement
## par Jenkins (namespace jenkins), aucune valeur en clair dans le repo, aucun
## clic dans l'UI. Crée aussi gitlab-webhook-token (secret partagé avec le
## webhook GitLab, cf. scripts/gitlab-init.sh — relancer `make gitlab-init`
## après celle-ci pour que le webhook soit créé côté GitLab). IDEMPOTENT (comme
## k8s-apps-secrets). Le token SonarQube reste une étape manuelle (cf.
## docs/apps-stack.md) : pas de mot de passe admin à scripter avant le
## changement forcé au premier login.
jenkins-credentials:
	@KUBECONFIG=$(KUBECONFIG_FILE) kubectl get secret harbor-credentials -n jenkins >/dev/null 2>&1 && \
		echo "harbor-credentials existe déjà — inchangé" || \
		{ HARBOR_PW=$$(KUBECONFIG=$(KUBECONFIG_FILE) kubectl get secret harbor-admin-password -n harbor -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 -d); \
		  KUBECONFIG=$(KUBECONFIG_FILE) kubectl create secret generic harbor-credentials -n jenkins \
			--type=kubernetes.io/basic-auth \
			--from-literal=username="admin" \
			--from-literal=password="$$HARBOR_PW"; \
		  KUBECONFIG=$(KUBECONFIG_FILE) kubectl label secret harbor-credentials -n jenkins jenkins.io/credentials-type=usernamePassword; \
		  KUBECONFIG=$(KUBECONFIG_FILE) kubectl annotate secret harbor-credentials -n jenkins jenkins.io/credentials-description="Harbor admin (auto, make jenkins-credentials)"; \
		  echo "harbor-credentials créé"; }
	@KUBECONFIG=$(KUBECONFIG_FILE) kubectl get secret gitlab-credentials -n jenkins >/dev/null 2>&1 && \
		echo "gitlab-credentials existe déjà — inchangé" || \
		{ GITLAB_PW=$$(KUBECONFIG=$(KUBECONFIG_FILE) kubectl get secret gitlab-initial-root-password -n gitlab -o jsonpath='{.data.password}' | base64 -d); \
		  KUBECONFIG=$(KUBECONFIG_FILE) kubectl create secret generic gitlab-credentials -n jenkins \
			--type=kubernetes.io/basic-auth \
			--from-literal=username="root" \
			--from-literal=password="$$GITLAB_PW"; \
		  KUBECONFIG=$(KUBECONFIG_FILE) kubectl label secret gitlab-credentials -n jenkins jenkins.io/credentials-type=usernamePassword; \
		  KUBECONFIG=$(KUBECONFIG_FILE) kubectl annotate secret gitlab-credentials -n jenkins jenkins.io/credentials-description="GitLab root (auto, make jenkins-credentials)"; \
		  echo "gitlab-credentials créé"; }
	@KUBECONFIG=$(KUBECONFIG_FILE) kubectl get secret gitlab-webhook-token -n jenkins >/dev/null 2>&1 && \
		echo "gitlab-webhook-token existe déjà — inchangé" || \
		{ WEBHOOK_TOKEN=$$(openssl rand -hex 20); \
		  KUBECONFIG=$(KUBECONFIG_FILE) kubectl create secret generic gitlab-webhook-token -n jenkins \
			--from-literal=token="$$WEBHOOK_TOKEN"; \
		  echo "gitlab-webhook-token créé"; }
	@KUBECONFIG=$(KUBECONFIG_FILE) kubectl get secret cosign-private-key -n jenkins >/dev/null 2>&1 && \
		echo "cosign-private-key existe déjà — inchangé" || \
		{ test -f $(COSIGN_KEY_FILE) || { echo "COSIGN_KEY_FILE introuvable ($(COSIGN_KEY_FILE)) — voir docs/cosign.md"; exit 1; }; \
		  KUBECONFIG=$(KUBECONFIG_FILE) kubectl create secret generic cosign-private-key -n jenkins \
			--from-file=text=$(COSIGN_KEY_FILE); \
		  KUBECONFIG=$(KUBECONFIG_FILE) kubectl label secret cosign-private-key -n jenkins jenkins.io/credentials-type=secretText; \
		  KUBECONFIG=$(KUBECONFIG_FILE) kubectl annotate secret cosign-private-key -n jenkins jenkins.io/credentials-description="Clé privée Cosign (auto, make jenkins-credentials)"; \
		  echo "cosign-private-key créé"; }
	@echo ""
	@echo "Reste à faire manuellement : générer un token SonarQube (admin -> My"
	@echo "Account -> Security -> Generate Token) et créer le secret sonarqube-token"
	@echo "(ns jenkins, type secretText) — cf. docs/apps-stack.md."

# ══════════════════════════════════════════════════════════
#  UTILITAIRES
# ══════════════════════════════════════════════════════════

.PHONY: clean help

## Nettoyer les fichiers temporaires
clean:
	rm -f $(ANSIBLE_DIR)/tf_outputs.json $(ANSIBLE_DIR)/tf_outputs_vault.json
	find . -name "*.retry" -delete
	find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
	@echo "Nettoyé"

## Afficher cette aide
help:
	@echo ""
	@echo "rncp-bc05 — Commandes disponibles"
	@echo "══════════════════════════════════════════"
	@echo ""
	@echo "  TERRAFORM CLUSTER"
	@echo "    make tf-cluster-init      terraform init (cluster)"
	@echo "    make tf-cluster-plan      terraform plan (cluster)"
	@echo "    make tf-cluster-apply     terraform apply (cluster)"
	@echo "    make tf-cluster-destroy   terraform destroy (cluster)"
	@echo "    make tf-cluster-output    terraform output (cluster)"
	@echo ""
	@echo "  TERRAFORM VAULT"
	@echo "    make tf-vault-init        terraform init (vault) — après tf-cluster-apply"
	@echo "    make tf-vault-plan        terraform plan (vault)"
	@echo "    make tf-vault-apply       terraform apply (vault)"
	@echo "    make tf-vault-destroy     terraform destroy (vault)"
	@echo "    make tf-vault-output      terraform output (vault)"
	@echo ""
	@echo "  ANSIBLE"
	@echo "    make ansible-inventory        Régénérer tf_outputs.json (cluster)"
	@echo "    make ansible-inventory-vault  Régénérer tf_outputs_vault.json"
	@echo "    make ping                     Tester la connectivité SSH (cluster)"
	@echo "    make ansible-k8s              Bootstrap complet K8s/RKE2"
	@echo "    make ansible-vault            Bootstrap complet Vault (sans init/unseal)"
	@echo ""
	@echo "  KUBERNETES — fondation cluster (GitOps, cf. docs/cluster-foundation.md)"
	@echo "    make kubeconfig           Récupérer le kubeconfig"
	@echo "    make nodes                Lister les nodes"
	@echo "    make k8s-secrets          Créer les Secrets (Scaleway CCM, OVH DNS-01)"
	@echo "    make k8s-ccm              Déployer le CCM Scaleway (lève le taint uninitialized, requis avant ArgoCD)"
	@echo "    make k8s-bootstrap-argocd Bootstrap ArgoCD + App-of-Apps (prend le relais sur le reste)"
	@echo "    make k8s-apps-secrets     Secrets admin stack applicative (Harbor, GitLab, SonarQube, Jenkins)"
	@echo "    make k8s-monitoring-secrets Secret admin Grafana (Phase 5, cf. docs/monitoring.md)"
	@echo "    make gitlab-init          Bootstrap projet GitLab firmware-poc (Phase 4/6, cf. docs/firmware-poc.md)"
	@echo "    make harbor-init          Créer le projet Harbor poc-ci (idempotent, requis avant tout push)"
	@echo "    make jenkins-credentials  Credentials Jenkins Harbor/GitLab (auto-découverte K8s, cf. docs/apps-stack.md)"
	@echo ""
	@echo "  UTILITAIRES"
	@echo "    make clean                Nettoyer les fichiers temporaires"
	@echo ""

.DEFAULT_GOAL := help
