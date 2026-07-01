#!/usr/bin/env python3
"""
Inventaire Ansible dynamique — lit :
  tf_outputs.json        généré par terraform -chdir=../terraform/cluster output -json
  tf_outputs_vault.json  généré par terraform -chdir=../terraform/vault output -json (optionnel)

Les deux states Terraform sont indépendants (cf. docs/poc-vs-prod.md), donc deux
fichiers d'outputs distincts plutôt qu'un seul.
"""

import json
import os
import sys

BASE_DIR = os.path.dirname(__file__)
TF_OUTPUTS_FILE = os.path.join(BASE_DIR, "tf_outputs.json")
TF_OUTPUTS_VAULT_FILE = os.path.join(BASE_DIR, "tf_outputs_vault.json")


def load_json(path, required):
    if not os.path.exists(path):
        if required:
            print(
                f"[inventory.py] Fichier {path} introuvable.\n"
                "Lancer d'abord : terraform -chdir=../terraform/cluster output -json > tf_outputs.json",
                file=sys.stderr,
            )
            sys.exit(1)
        return None
    with open(path) as f:
        return json.load(f)


def build_inventory():
    outputs = load_json(TF_OUTPUTS_FILE, required=True)
    vault_outputs = load_json(TF_OUTPUTS_VAULT_FILE, required=False)

    cp_ip = outputs["control_plane_ip_public"]["value"]
    w01_ip = outputs["worker01_ip_public"]["value"]
    w02_ip = outputs["worker02_ip_public"]["value"]

    hostvars = {
        "rncp-bc05-cp-01": {"ansible_host": cp_ip},
        "rncp-bc05-worker-01": {"ansible_host": w01_ip},
        "rncp-bc05-worker-02": {"ansible_host": w02_ip},
    }
    groups = {
        "control_plane": {"hosts": ["rncp-bc05-cp-01"]},
        "workers": {"hosts": ["rncp-bc05-worker-01", "rncp-bc05-worker-02"]},
        "k8s_cluster": {"children": ["control_plane", "workers"]},
    }

    if vault_outputs is not None:
        vault_ip = vault_outputs["vault_ip_public"]["value"]
        hostvars["rncp-bc05-vault"] = {"ansible_host": vault_ip}
        groups["vault"] = {"hosts": ["rncp-bc05-vault"]}

    groups["_meta"] = {"hostvars": hostvars}
    groups["all"] = {
        "vars": {
            "ansible_user": "almalinux",
            "ansible_ssh_private_key_file": "~/.ssh/id_ed25519-scw",
            "ansible_ssh_common_args": "-o StrictHostKeyChecking=no",
        }
    }
    return groups


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--list":
        print(json.dumps(build_inventory()))
    elif len(sys.argv) == 3 and sys.argv[1] == "--host":
        print(json.dumps({}))
    else:
        print("Usage: inventory.py --list | --host <hostname>", file=sys.stderr)
        sys.exit(1)
