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

.PHONY: kubeconfig nodes k8s-secrets k8s-ccm k8s-bootstrap-argocd

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
	@echo ""
	@echo "  UTILITAIRES"
	@echo "    make clean                Nettoyer les fichiers temporaires"
	@echo ""

.DEFAULT_GOAL := help
