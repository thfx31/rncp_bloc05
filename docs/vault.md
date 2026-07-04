# Vault — installation, init, unseal

## Ce que fait le rôle Ansible `vault`

- Installe Vault (dépôt RPM officiel HashiCorp)
- Génère un certificat TLS auto-signé (`community.crypto`), listener HTTPS sur `:8200`
- Configure le storage `raft` single-node (`/opt/vault/data`)
- Ouvre les ports firewalld (`8200` API, `8201` cluster — inutile en single-node
  mais ouvert par cohérence)
- Démarre et active le service `vault` (systemd)

Résultat après `make ansible-vault` : Vault tourne, **scellé et non initialisé**.

## Ce que le rôle NE fait PAS (volontairement)

`vault operator init` et `vault operator unseal` ne sont **pas automatisés** —
limite POC assumée (cf. `CONTEXT.md`), pour ne pas faire transiter les unseal
keys / le root token par du code Ansible versionné ou des logs de playbook.
À faire à la main, une seule fois :

```bash
export VAULT_ADDR="https://<ip-publique-vault>:8200"
export VAULT_SKIP_VERIFY=true   # certificat auto-signé, POC uniquement

# Initialisation (une seule fois — génère 5 unseal keys + 1 root token)
vault operator init

# Conserver les 5 unseal keys et le root token dans un endroit sûr
# (gestionnaire de mots de passe personnel — PAS dans le repo, PAS dans un fichier
# non chiffré sur la VM)

# Unseal (à refaire à chaque redémarrage du service vault — 3 clés sur 5 suffisent)
vault operator unseal   # x3, avec 3 unseal keys différentes

vault status
```

## Rebuild complet à chaque session (destroy/recreate)

En pratique, `terraform/cluster` **et** `terraform/vault` sont détruits à la fin
de chaque session de travail (coût Scaleway) et recréés au début de la suivante.
La VM Vault repart donc de zéro à chaque fois : le storage `raft`
(`/opt/vault/data`) est vidé avec l'instance. Conséquence : il n'y a **pas
d'unseal keys/root token à conserver dans la durée** — un nouvel
`vault operator init` doit être rejoué à chaque recréation, ce qui génère un
nouveau jeu de clés à chaque fois.

Séquence complète de rebuild, dans l'ordre :

```bash
# 1. Cluster (réseau privé requis par le data source de terraform/vault)
make tf-cluster-apply
make ansible-k8s

# 2. Vault (VM dédiée)
make tf-vault-apply
make ansible-vault

# 3. Init + unseal manuel (à chaque recréation de la VM Vault)
export VAULT_ADDR="https://<ip-publique-vault>:8200"
export VAULT_SKIP_VERIFY=true

vault operator init
# → note les 5 unseal keys + le root token le temps de la session
#   (fichier local non versionné, ou gestionnaire de mots de passe —
#   jamais dans le repo, jamais dans un fichier commité)

vault operator unseal   # x3, avec 3 clés différentes parmi les 5
vault status            # doit afficher "Sealed: false"
```

Si seul le service `vault` redémarre (VM conservée, pas de destroy), l'étape
`vault operator init` est déjà faite : passer directement à `vault operator
unseal` avec les clés de la session en cours.

## Poids sur la démo / soutenance

Argument à l'oral si questionné sur l'unseal manuel : en production, on
utiliserait l'auto-unseal (KMS cloud, Transit d'un autre Vault, ou HSM) —
hors scope volontaire pour un POC 5 minutes de démo, où Vault est démarré à
l'avance et reste unsealed pendant la soutenance.

## À venir (Phase 4)

- Intégration Jenkins via auth K8s (un secret ciblé, ex. creds Harbor)
- ESO (External Secrets Operator) — pont Vault → K8s Secrets
