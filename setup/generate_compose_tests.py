#!/usr/bin/env python
import os
import jinja2
from gluetool.utils import load_yaml, Command
from gluetool.glue import GlueCommandError

GUEST_SETUP_PATH = "tests/testing-farm/public"
TEMPLATE_FILENAME = "compose-test-template.yaml.j2"
COMPOSES_FILEPATH = "terragrunt/environments/dev/artemis/config/variables_images.yaml"
TEST_FILENAME = "compose-{}-{}.yaml"
ARCHES = ['x86_64', 'aarch64']

def check_test_exists(compose: str, arch: str) -> bool:
    """
    Check if a test needs to be created
    """
    test_filepath = os.path.join(GUEST_SETUP_PATH, TEST_FILENAME.format(compose, arch))
    return os.path.isfile(test_filepath)


def generate_file(compose: str, arch: str) -> None:
    test_filepath = os.path.join(GUEST_SETUP_PATH, TEST_FILENAME.format(compose, arch))
    variables = {
        'COMPOSE': compose,
        'ARCH': arch,
    }

    template_filepath = os.path.join(GUEST_SETUP_PATH, TEMPLATE_FILENAME)
    file_loader = jinja2.FileSystemLoader('.')
    env = jinja2.Environment(loader=file_loader)
    template = env.get_template(template_filepath)

    with open(test_filepath, 'w') as test_file:
        print(template.render(variables), file=test_file)


def main() -> None:
    composes = load_yaml(COMPOSES_FILEPATH)['composes']
    for _, value in composes.items():
        for arch in ARCHES:
            if not arch in value:
                continue

            if not check_test_exists(value['compose'], arch):
                print("Generating a new {} test".format(TEST_FILENAME.format(value['compose'], arch)))
                generate_file(value['compose'], arch)

            else:
                print("The {} test exists, skipping".format(TEST_FILENAME.format(value['compose'], arch)))


if __name__ == '__main__':
    main()
