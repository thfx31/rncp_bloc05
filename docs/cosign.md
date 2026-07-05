# Cosign — signature d'images

## Quoi

[Cosign](https://github.com/sigstore/cosign) (projet Sigstore) signe une image de
conteneur : il calcule une signature sur le digest (hash SHA256 du manifeste), et pousse
cette signature comme un artefact OCI séparé dans le même registre (Harbor), sans modifier
l'image d'origine. `cosign verify` permet ensuite de vérifier qu'une image donnée a bien
été produite par le pipeline et n'a pas été altérée, ni remplacée par une image tierce
poussée directement dans Harbor en contournant le pipeline CI.

## Pourquoi clé statique, pas keyless

Sigstore recommande en priorité le mode **keyless** (certificat éphémère signé par Fulcio
via un token OIDC, transparence publique dans le log Rekor) — pas de clé privée à gérer du
tout. Choix POC : **clé statique** (`cosign generate-key-pair`) à la place, pour ne pas
dépendre de la joignabilité de `fulcio.sigstore.dev`/`rekor.sigstore.dev` ni d'un OIDC
issuer externe le jour de la soutenance — une démo doit rester autonome et fiable sans
dépendre d'un service tiers.

En prod, la piste naturelle serait Vault comme backend KMS
(`cosign sign --key hashivault://<key-name>`, moteur `transit` de Vault) : la clé privée ne
sort jamais de Vault, Cosign lui envoie juste le digest à signer. Non implémenté dans ce
POC (aurait fait dépendre la capacité de signer d'un Vault unsealed).

## Où est la clé

- **Clé privée** (`cosign.key`) : générée hors repo, dans `~/.cosign/rncp-bc05/` sur le
  poste opérateur — **jamais committée**. Passphrase vide (`COSIGN_PASSWORD=""`) pour
  permettre une signature non-interactive depuis un pipeline Jenkins.
- **Clé publique** (`cosign.pub`) : committée dans
  `kubernetes/01-apps/cosign-public-key/cosign.pub` — ce n'est pas un secret, c'est elle
  que la policy Kyverno (`verifyImages`) ira lire pour vérifier les signatures à
  l'admission.

## Commandes

```bash
# Génération (déjà faite pour ce POC)
COSIGN_PASSWORD="" cosign generate-key-pair

# Signer une image poussée sur Harbor
cosign sign --key cosign.key --yes harbor.k8s.yplank.fr/<project>/<image>:<tag>

# Vérifier
cosign verify --key cosign.pub harbor.k8s.yplank.fr/<project>/<image>:<tag>
```

`cosign verify` échoue explicitement (exit non-zero, message clair) si l'image n'a jamais
été signée, ou si la signature ne correspond pas à la clé publique fournie — c'est ce
comportement que Kyverno réutilise pour bloquer un déploiement à l'admission (cf.
`docs/kyverno.md`, à venir).

## Arbitrage POC vs prod

Voir `docs/poc-vs-prod.md` — clé statique + passphrase vide, vs keyless/Sigstore ou Vault
Transit KMS en prod.
