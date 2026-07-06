# Checkov / tfsec — scan statique IaC

## Quoi

`.github/workflows/lint-iac.yml` — scan statique de sécurité sur
`terraform/` et `ansible/`, déclenché sur chaque push/PR touchant ces
dossiers. Deux outils complémentaires sur la partie Terraform (tfsec +
Checkov), Checkov seul sur la partie Ansible, plus `ansible-lint` (qualité de
code, pas spécifiquement sécurité) et `terraform fmt`/`validate` (syntaxe).

## Pourquoi GitHub Actions, pas Jenkins

Le code IaC (`terraform/`, `ansible/`) vit sur GitHub (source de vérité de
l'infra), distinct du code applicatif (`app/firmware-poc/`) qui vit sur
GitLab et passe par le pipeline Jenkins. Deux couches de scan séparées :
Jenkins/Checkov scanne le `Dockerfile` d'une image applicative, ce workflow
scanne les définitions d'infrastructure elle-même — avant même qu'un
`terraform apply` ne tourne.

## Pourquoi `soft_fail: true` au démarrage

Premier passage sur un repo qui n'a jamais été scanné : risque de bruit
(faux positifs, règles non pertinentes pour un POC — ex. chiffrement au
repos sur une ressource de démo). `soft_fail` laisse le workflow réussir
même si des findings remontent, le temps de les trier et d'ajouter des
`skip` documentés pour ceux qui ne s'appliquent pas. À bascule en hard-fail
avant la soutenance, une fois le bruit éliminé.

## Comment lire un skip

Si un check est explicitement ignoré (`--skip-check` tfsec/Checkov, ou
`# noqa` ansible-lint), un commentaire dans le code doit expliquer pourquoi
— cf. `docs/poc-vs-prod.md` pour l'arbitrage général.
