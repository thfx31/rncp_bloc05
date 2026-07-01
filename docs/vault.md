# Vault — installation, init, unseal

## Ce que fait le rôle Ansible `vault`

- Installe Vault (dépôt RPM officiel HashiCorp)
- Génère un certificat TLS auto-signé (`community.crypto`), listener HTTPS sur `:8200`
- Configure le storage `raft` single-node (`/opt/vault/data`)
- Ouvre les ports firewalld (`8200` API, `8201` cluster — inutile en single-node
  mais ouvert par cohérence)
- Démarre et active le service `vault` (systemd)

Résultat après `make bootstrap-vault` : Vault tourne, **scellé et non initialisé**.

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

## Poids sur la démo / soutenance

Argument à l'oral si questionné sur l'unseal manuel : en production, on
utiliserait l'auto-unseal (KMS cloud, Transit d'un autre Vault, ou HSM) —
hors scope volontaire pour un POC 5 minutes de démo, où Vault est démarré à
l'avance et reste unsealed pendant la soutenance.

## À venir (Phase 4)

- Intégration Jenkins via auth K8s (un secret ciblé, ex. creds Harbor)
- ESO (External Secrets Operator) — pont Vault → K8s Secrets
