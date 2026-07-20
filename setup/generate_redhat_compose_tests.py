#!/usr/bin/env python
import os

import jinja2
import requests
import yaml
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

TESTS_PATH = "tests/testing-farm/redhat"
TEMPLATE_FILENAME = "compose-test-template.yaml.j2"
TEST_FILENAME = "compose-{}-{}.yaml"
ARCHES = ["x86_64", "aarch64"]
# These composes are skipped because they are provisioned by Beaker on aarch64
AARCH64_UNSUPPORTED = ["CentOS-Stream-8", "CentOS-Stream-9", "CentOS-Stream-10", "Fedora-45", "Fedora-Rawhide", "RHEL-7.9-Nightly"]
MATRIX_URL = "https://gitlab.com/testing-farm/profiles/-/raw/main/matrix.yaml"


def fetch_composes(retries: int = 3, timeout: int = 30) -> list[str]:
    session = requests.Session()
    session.mount('https://', HTTPAdapter(max_retries=Retry(
        total=retries, backoff_factor=2, status_forcelist=[500, 502, 503, 504]
    )))
    response = session.get(MATRIX_URL, timeout=timeout)
    response.raise_for_status()

    matrix = yaml.safe_load(response.text)
    return sorted({entry['image'] for entry in matrix['virtual']['redhat']})


def generate_file(compose: str, arch: str) -> None:
    test_filepath = os.path.join(TESTS_PATH, TEST_FILENAME.format(compose, arch))

    template_filepath = os.path.join(TESTS_PATH, TEMPLATE_FILENAME)
    file_loader = jinja2.FileSystemLoader('.')
    env = jinja2.Environment(loader=file_loader)
    template = env.get_template(template_filepath)

    with open(test_filepath, 'w') as test_file:
        print(template.render(COMPOSE=compose, ARCH=arch), file=test_file)


def arches_for_compose(compose: str) -> list[str]:
    return ["x86_64"] if compose in AARCH64_UNSUPPORTED else ARCHES


def cleanup_stale(expected_composes: list[str]) -> None:
    expected_files = {TEST_FILENAME.format(c, a) for c in expected_composes for a in arches_for_compose(c)}

    for filename in os.listdir(TESTS_PATH):
        if filename.startswith('compose-') and filename.endswith('.yaml') and filename not in expected_files:
            filepath = os.path.join(TESTS_PATH, filename)
            print(f"Removing stale test {filename}")
            os.remove(filepath)


def main() -> None:
    composes = fetch_composes()
    print(f"Found {len(composes)} composes from matrix.yaml: {', '.join(composes)}")

    for compose in composes:
        for arch in arches_for_compose(compose):
            print(f"Generating {TEST_FILENAME.format(compose, arch)}")
            generate_file(compose, arch)

    cleanup_stale(composes)


if __name__ == '__main__':
    main()
