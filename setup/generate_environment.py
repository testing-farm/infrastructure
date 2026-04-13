# This script is used to generate `environment.yaml` files for each `citool-config` inside the dev environment. These
# `environment.yaml` files are consumed by gluetool and contain credentials and values specific to each dev environment.
# This script can be executed using `make`.
#
# For the citool-config container image workflow, generated files are written to the .generated/ directory,
# which contains a selection of citool-config files for local execution used in CI as well as credentials
# and environment-specific values.

import os
import stat
import subprocess
import sys
import time

import requests
import ruamel.yaml

from ansible.constants import DEFAULT_VAULT_ID_MATCH
from ansible.parsing.vault import VaultLib, VaultSecret
from jinja2 import Template

from typing import Union

SecretsType = dict[str, Union[str, 'SecretsType']]

SUPPORTED_ENVIRONMENTS = ['dev', 'staging', 'staging/ci']
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

        # The Artemis API domain is a freshly created `external-dns` record in Route53. Even after
        # `wait_artemis_available.sh` sees a single successful lookup, DNS can still transiently return
        # NXDOMAIN due to negative caching and Route53 eventual consistency, so retry on failure.
        about_url = f"http://{artemis_api_domain}/current/about"
        retry_timeout = 300
        start_time = time.monotonic()
        while True:
            try:
                response = requests.get(about_url, allow_redirects=True)
                break
            except requests.exceptions.ConnectionError as exc:
                if time.monotonic() - start_time >= retry_timeout:
                    raise Exception(f"Artemis about endpoint '{about_url}' was not reachable within {retry_timeout} seconds.") from exc
                print(f"Artemis about endpoint '{about_url}' not reachable yet, retrying ...")
                time.sleep(5)

        if response.status_code != 200:
            raise Exception(f"Artemis about endpoint '{response.url}' returned status code '{response.status_code}'.")

        context.update({
            'artemis_api_domain': artemis_api_domain,
            'staging_ci_suffix': f"-{os.getenv('STAGING_CI_SUFFIX')}" if os.getenv('STAGING_CI_SUFFIX') else ''
        })

    # Create .generated directory with secrets used for citool-config container image tests
    source_dirpath = os.path.join('terragrunt', 'environments', environment, WORKER, 'citool-config')
    output_dirpath = os.path.join('.generated', environment, WORKER, 'citool-config')
    os.makedirs(output_dirpath, exist_ok=True)

    template_filepath = os.path.join(source_dirpath, 'environment.yaml.j2')
    result_template_filepath = os.path.join(output_dirpath, 'environment.yaml')

    print('Generating "{}"'.format(result_template_filepath))

    with open(template_filepath, 'r') as f:
        template = f.read()

    template_rendered = Template(template).render(context)

    with open(result_template_filepath, 'w') as f:
        print(template_rendered, file=f)

    worker_artemis_ssh_key = f'{TERRAGRUNT_ENV_DIR}/{environment}/{WORKER}/citool-config/id_rsa_artemis'
    worker_artemis_ssh_key_decrypted = os.path.join(output_dirpath, 'id_rsa_artemis.decrypted')

    print(f'Decrypting "{worker_artemis_ssh_key}"')

    with open(worker_artemis_ssh_key, 'r') as f:
        ssh_key_encrypted = f.read()

    print(f'Writing "{worker_artemis_ssh_key_decrypted}"')

    with open(worker_artemis_ssh_key_decrypted, 'wb') as f:
        f.write(vault.decrypt(ssh_key_encrypted))

    print(f'Setting permissions of "{worker_artemis_ssh_key_decrypted}" to 600')
    os.chmod(worker_artemis_ssh_key_decrypted, stat.S_IRUSR | stat.S_IWUSR)

    # Generate secret config files for CONFIG-SECRETS mount
    secrets_config_dir = os.path.join(output_dirpath, 'config')
    os.makedirs(secrets_config_dir, exist_ok=True)

    # Resolve the API key from credentials
    # NOTE: dev local environment uses staging TF API
    environment_credentials = environment
    if environment == 'dev' and WORKER == 'worker-local':
        environment_credentials = 'staging'
    api_key = credentials_decrypted['credentials']['testing_farm'][environment_credentials]['public']['users']['worker']['token']

    testing_farm_request_path = os.path.join(secrets_config_dir, 'testing-farm-request')
    print(f'Generating "{testing_farm_request_path}"')
    with open(testing_farm_request_path, 'w') as f:
        f.write(f'[default]\napi-key = {api_key}\n')

    artemis_config_path = os.path.join(secrets_config_dir, 'artemis')
    print(f'Generating "{artemis_config_path}"')
    with open(artemis_config_path, 'w') as f:
        f.write('[default]\nssh-key = ${config_root}/id_rsa_artemis.decrypted\n')


if __name__ == '__main__':
    main()
