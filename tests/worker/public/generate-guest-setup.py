#!/usr/bin/env python
import os
import jinja2
import requests
from gluetool.utils import load_yaml, Command
from gluetool.glue import GlueCommandError

GUEST_SETUP_PATH = "tests/worker/public/pipeline"
TEMPLATE_FILENAME = "guest-setup-template.yaml.j2"
COMPOSES_FILEPATH = "terraform/environments/dev/config/variables_images.yaml"
TEST_FILENAME = "compose-{}-{}.yaml"
PLAN = "/testing-farm/sanity"
GIT_REF = "main"
GIT_URL = "https://gitlab.com/testing-farm/tests"
ARCHES = ['x86_64', 'aarch64']

def check_test_exists(compose: str, arch: str) -> bool:
    """
    Check if a test needs to be created
    """
    test_filepath = os.path.join(GUEST_SETUP_PATH, TEST_FILENAME.format(compose, arch))
    return os.path.isfile(test_filepath)


def generate_file(request_id: str, compose: str, arch: str) -> None:
    test_filepath = os.path.join(GUEST_SETUP_PATH, TEST_FILENAME.format(compose, arch))
    variables = {
        'REQUEST_ID': request_id,
        'COMPOSE': compose,
        'ARCH': arch,
    }

    template_filepath = os.path.join(GUEST_SETUP_PATH, TEMPLATE_FILENAME)
    file_loader = jinja2.FileSystemLoader('.')
    env = jinja2.Environment(loader=file_loader)
    template = env.get_template(template_filepath)

    with open(test_filepath, 'w') as test_file:
        print(template.render(variables), file=test_file)


def create_request(arch: str, compose: str) -> str:
    data = {
        'api_key': os.environ['TESTING_FARM_API_TOKEN'],
        'test': {
            'fmf': {
                'name': PLAN,
                'ref': GIT_REF,
                'url': GIT_URL
            }
        },
        'environments': [{
            'arch': arch,
            'os': {
                'compose': compose
            }
        }]
    }
    url = "{}/requests".format(os.environ['TESTING_FARM_API_URL'])
    try:
        response = requests.post(url, json=data)
    except requests.RequestException as exc:
        raise exc

    return response.json()['id']


def main() -> None:
    composes = load_yaml(COMPOSES_FILEPATH)['composes']
    for _, value in composes.items():
        for arch in ARCHES:
            if not arch in value:
                continue

            if not check_test_exists(value['compose'], arch):
                print("Generating a new {} test".format(TEST_FILENAME.format(value['compose'], arch)))
                request_id = create_request(arch, value['compose'])
                generate_file(request_id, value['compose'], arch)

            else:
                print("The {} test exists, skipping".format(TEST_FILENAME.format(value['compose'], arch)))


if __name__ == '__main__':
    for envvar in ['TESTING_FARM_API_URL', 'TESTING_FARM_API_TOKEN']:
        if not envvar in os.environ:
            print('The {} environment variable was not been found'.format(envvar))
            exit(1)
    main()
