#!/usr/bin/env python
import os

import jinja2
import requests
import yaml

TESTS_PATH = "tests/testing-farm/redhat"
TEMPLATE_FILENAME = "compose-test-template.yaml.j2"
TEST_FILENAME = "compose-{}-x86_64.yaml"
MATRIX_URL = "https://gitlab.com/testing-farm/profiles/-/raw/main/matrix.yaml"


def fetch_composes() -> list[str]:
    response = requests.get(MATRIX_URL)
    response.raise_for_status()

    matrix = yaml.safe_load(response.text)
    return sorted({entry['image'] for entry in matrix['virtual']['redhat']})


def generate_file(compose: str) -> None:
    test_filepath = os.path.join(TESTS_PATH, TEST_FILENAME.format(compose))

    template_filepath = os.path.join(TESTS_PATH, TEMPLATE_FILENAME)
    file_loader = jinja2.FileSystemLoader('.')
    env = jinja2.Environment(loader=file_loader)
    template = env.get_template(template_filepath)

    with open(test_filepath, 'w') as test_file:
        print(template.render(COMPOSE=compose), file=test_file)


def cleanup_stale(expected_composes: list[str]) -> None:
    expected_files = {TEST_FILENAME.format(c) for c in expected_composes}

    for filename in os.listdir(TESTS_PATH):
        if filename.startswith('compose-') and filename.endswith('.yaml') and filename not in expected_files:
            filepath = os.path.join(TESTS_PATH, filename)
            print(f"Removing stale test {filename}")
            os.remove(filepath)


def main() -> None:
    composes = fetch_composes()
    print(f"Found {len(composes)} composes from matrix.yaml: {', '.join(composes)}")

    for compose in composes:
        test_filepath = os.path.join(TESTS_PATH, TEST_FILENAME.format(compose))
        if os.path.isfile(test_filepath):
            print(f"The {TEST_FILENAME.format(compose)} test exists, skipping")
        else:
            print(f"Generating a new {TEST_FILENAME.format(compose)} test")
            generate_file(compose)

    cleanup_stale(composes)


if __name__ == '__main__':
    main()
