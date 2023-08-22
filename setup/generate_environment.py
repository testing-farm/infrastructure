# This script is used to generate `environment.yaml` files for each `citool-config` inside the dev environment. These
# `environment.yaml` files are consumed by gluetool and contain credentials and values specific to each dev environment.
# This script can be executed using `make`.

import os
import ruamel.yaml

from ansible.constants import DEFAULT_VAULT_ID_MATCH
from ansible.parsing.vault import VaultLib, VaultSecret
from jinja2 import Template

from typing import Union


SecretsType = dict[str, Union[str, 'SecretsType']]
SUPPORTED_ENVIRONMENTS = ['dev', 'staging']


def main() -> None:
    with open('.vault_pass', 'r') as f:
        vault_pass = f.read().strip()

    with open(os.path.join('secrets', 'credentials.yaml'), 'r') as f:
        credentials_encrypted = f.read()

    vault = VaultLib([(DEFAULT_VAULT_ID_MATCH, VaultSecret(vault_pass.encode()))])
    credentials_decrypted: SecretsType = ruamel.yaml.safe_load(vault.decrypt(credentials_encrypted))

    for environment in SUPPORTED_ENVIRONMENTS:
        template_dirpath = os.path.join('terragrunt', 'environments', environment, 'worker', 'citool-config')
        template_filepath = os.path.join(template_dirpath, 'environment.yaml.j2')
        result_template_filepath = os.path.join(template_dirpath, 'environment.yaml')

        print('Generating `{}`...'.format(result_template_filepath))

        with open(template_filepath, 'r') as f:
            template = f.read()

        template_rendered = Template(template).render({**credentials_decrypted, **dict(os.environ)})

        with open(result_template_filepath, 'w') as f:
            print(template_rendered, file=f)


if __name__ == '__main__':
    main()
