# This script is used to generate `environment.yaml` files for each `citool-config` inside the dev environment. These
# `environment.yaml` files are consumed by gluetool and contain credentials and values specific to each dev environment.
# This script can be executed using `make`.

import os
import stat
import subprocess
import sys

import ruamel.yaml

from ansible.constants import DEFAULT_VAULT_ID_MATCH
from ansible.parsing.vault import VaultLib, VaultSecret
from jinja2 import Template

from typing import Union

SecretsType = dict[str, Union[str, 'SecretsType']]

SUPPORTED_ENVIRONMENTS = ['dev', 'staging']
TERRAGRUNT_ENV_DIR=f'{os.environ["PROJECT_ROOT"]}/terragrunt/environments'
# Use this variable to override the artemis deployment name, e.g. `artemis-integration`
# Use none to ignore artemis deployment (for container only testing it is not needed)
ARTEMIS_DEPLOYMENT = os.environ.get('ARTEMIS_DEPLOYMENT', 'artemis')
WORKER = os.environ.get('WORKER', 'worker-public')
SECRETS_FILE = os.environ.get('SECRETS_FILE')
VAULT_PASS = '.vault_pass'


def main() -> None:
    if not SECRETS_FILE or not os.path.exists(SECRETS_FILE):
        raise Exception('SECRETS_FILE not found in the environment.')

    if not os.path.exists(VAULT_PASS):
        raise Exception(f'Vault password file {VAULT_PASS} not found.')

    with open(VAULT_PASS, 'r') as f:
        vault_pass = f.read().strip()

    with open(SECRETS_FILE, 'r') as f:
        credentials_encrypted = f.read()

    vault = VaultLib([(DEFAULT_VAULT_ID_MATCH, VaultSecret(vault_pass.encode()))])
    credentials_decrypted: SecretsType = ruamel.yaml.YAML(typ='safe').load(vault.decrypt(credentials_encrypted))

    environment = sys.argv[1] if len(sys.argv) == 2 else None

    if not environment:
        raise Exception('Script requires a single argument specifying the environment name.')

    if environment not in SUPPORTED_ENVIRONMENTS:
        raise Exception(f'Unsupported environment "{environment}".')

    context = {
        **credentials_decrypted,
        **dict(os.environ),
    }

    if ARTEMIS_DEPLOYMENT.lower() != "none":
        print(f'Checking for Artemis "{environment}" deployment ...')
        artemis_env_path = f'{TERRAGRUNT_ENV_DIR}/{environment}/{ARTEMIS_DEPLOYMENT}'

        if not os.path.isdir(artemis_env_path):
            raise Exception(f'No Artemis deployment "{ARTEMIS_DEPLOYMENT}" found in "{environment}" environment.')

        artemis_api_domain = subprocess.check_output(
            ['terragrunt', 'output', '--raw', 'artemis_api_domain'],
            env={
                **os.environ,
                'TERRAGRUNT_WORKING_DIR': artemis_env_path
            },
        ).decode(sys.stdout.encoding)

        if 'No outputs found' in artemis_api_domain:
            raise Exception(f'No Artemis hostname found, "{ARTEMIS_DEPLOYMENT}" not deployed in "{environment}" environment?')

        context.update({
            'artemis_api_domain': artemis_api_domain
        })

    template_dirpath = os.path.join('terragrunt', 'environments', environment, WORKER, 'citool-config')
    template_filepath = os.path.join(template_dirpath, 'environment.yaml.j2')
    result_template_filepath = os.path.join(template_dirpath, 'environment.yaml')

    print('Generating "{}"'.format(result_template_filepath))

    with open(template_filepath, 'r') as f:
        template = f.read()

    template_rendered = Template(template).render(context)

    with open(result_template_filepath, 'w') as f:
        print(template_rendered, file=f)

    worker_artemis_ssh_key = f'{TERRAGRUNT_ENV_DIR}/{environment}/{WORKER}/citool-config/id_rsa_artemis'
    worker_artemis_ssh_key_decrypted = f'{worker_artemis_ssh_key}.decrypted'

    print(f'Decrypting "{worker_artemis_ssh_key}"')

    with open(worker_artemis_ssh_key, 'r') as f:
        ssh_key_encrypted = f.read()

    print(f'Writing "{worker_artemis_ssh_key}"')

    with open(worker_artemis_ssh_key_decrypted, 'wb') as f:
        f.write(vault.decrypt(ssh_key_encrypted))

    print(f'Setting permissions of "{worker_artemis_ssh_key_decrypted}" to 600')
    os.chmod(worker_artemis_ssh_key_decrypted, stat.S_IRUSR | stat.S_IWUSR)

if __name__ == '__main__':
    main()
