#!/usr/bin/env python
import argparse
from pathlib import Path

import jinja2
import requests
import yaml
from gluetool.utils import load_yaml
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

TESTS_PATH = Path('tests/testing-farm')
TEMPLATE_FILENAME = 'compose-test-template.yaml.j2'
COMPOSES_FILEPATH = 'terragrunt/environments/dev/artemis/config/variables_images.yaml'
TEST_FILENAME = 'compose-{}-{}.yaml'
ARCHES = ['x86_64', 'aarch64']
# These Red Hat composes are provisioned by Beaker on aarch64.
AARCH64_UNSUPPORTED = ['CentOS-Stream-8', 'CentOS-Stream-9', 'CentOS-Stream-10',
                      'Fedora-45', 'Fedora-Rawhide', 'RHEL-7.9-Nightly']
MATRIX_URL = 'https://gitlab.com/testing-farm/profiles/-/raw/main/matrix.yaml'


def fetch_redhat_composes(retries: int = 3, timeout: int = 30) -> list[str]:
    """Fetch the Red Hat compose catalog from the profiles matrix."""
    with requests.Session() as session:
        session.mount('https://', HTTPAdapter(max_retries=Retry(
            total=retries, backoff_factor=2, status_forcelist=[500, 502, 503, 504]
        )))
        response = session.get(MATRIX_URL, timeout=timeout)
        response.raise_for_status()

    matrix = yaml.safe_load(response.text)
    return sorted({entry['image'] for entry in matrix['virtual']['redhat']})


def load_compose_matrix(ranch: str) -> list[tuple[str, str]]:
    """Return the compose/architecture pairs supported by the selected ranch."""
    if ranch == 'public':
        composes = load_yaml(COMPOSES_FILEPATH)['composes']
        return [(value['compose'], arch) for value in composes.values() for arch in ARCHES if arch in value]

    return [(compose, arch) for compose in fetch_redhat_composes() for arch in ARCHES
            if compose not in AARCH64_UNSUPPORTED or arch == 'x86_64']


def generate_file(tests_path: Path, compose: str, arch: str) -> None:
    template = jinja2.Environment(loader=jinja2.FileSystemLoader(str(tests_path))).get_template(TEMPLATE_FILENAME)
    test_filepath = tests_path / TEST_FILENAME.format(compose, arch)
    test_filepath.write_text(template.render(COMPOSE=compose, ARCH=arch) + '\n')


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description='Generate compose scenarios for the public or Red Hat ranch.')
    parser.add_argument('--ranch', choices=['public', 'redhat'], default='public')
    args = parser.parse_args(argv)

    tests_path = TESTS_PATH / args.ranch
    matrix = load_compose_matrix(args.ranch)
    expected_files = {TEST_FILENAME.format(compose, arch) for compose, arch in matrix}

    for compose, arch in matrix:
        filename = TEST_FILENAME.format(compose, arch)
        if args.ranch == 'public' and (tests_path / filename).is_file():
            print('The {} test exists, skipping'.format(filename))
            continue

        print('Generating {}'.format(filename))
        generate_file(tests_path, compose, arch)

    if args.ranch == 'redhat':
        for test_filepath in tests_path.glob('compose-*.yaml'):
            if test_filepath.name not in expected_files:
                print('Removing stale test {}'.format(test_filepath.name))
                test_filepath.unlink()


if __name__ == '__main__':
    main()
