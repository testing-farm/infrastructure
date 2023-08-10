#!/usr/bin/env python

import requests
import re
import ruamel.yaml
import shutil
import tempfile


VARIABLES_IMAGES_FILEPATHS = [
    "terraform/environments/dev/config/variables_images.yaml",
    "terraform/environments/staging/config/variables_images.yaml",
    "terraform/environments/production/config/variables_images.yaml",
]
ARCHES = ['x86_64', 'aarch64']
ARTEMIS_URL = 'http://artemis.production.testing-farm.io/v0.0.55/'

Y = ruamel.yaml.YAML()
Y.indent(sequence=2, mapping=2, offset=2)


def get_available_images() -> list[str]:
    return requests.get('{}_cache/pools/fedora-aws-x86_64/image-info'.format(ARTEMIS_URL)).json()


def update_variables_images_file(variables_images_filepath: str, available_images: list[str]) -> None:
    with open(variables_images_filepath, 'r') as f:
        composes = Y.load(f)

    for compose in composes['composes'].values():
        for arch in ARCHES:
            compose_name = compose[arch]['image']
            print('Updating compose "{}"...'.format(compose_name))

            # Construct a regex from the current image to match possible candidates with newer date, e.g.
            # 'Fedora-Cloud-Base-37-20230803.0.x86_64-hvm-us-east-2-gp3-0' ->
            # 'Fedora-Cloud-Base-37-(\d{8}).0.x86_64-hvm-us-east-2-gp3-0'
            compose_regex = re.sub('\d{8}', r'(\\d{8})', compose_name)

            if compose_name == compose_regex:
                print('No "YYYYMMDD" pattern found in compose {}, continuing...\n'.format(compose_name))
                continue

            # Match all candidates of the same compose with different dates
            matched_composes = []
            for available_compose in available_images:
                match = re.fullmatch(compose_regex, available_compose)
                if match:
                    matched_composes.append(match)

            # Find the newest one
            newest_compose = None
            for match in matched_composes:
                if not newest_compose or match.group(1) > newest_compose.group(1):
                    newest_compose = match
            print('Newest compose found: "{}"'.format(match.group(0)))

            # If the newest one differs from the current one, bump it
            if newest_compose and newest_compose.group(0) != compose_name:
                print('-"{}"\n+"{}"'.format(compose_name, newest_compose.group(0)))
                compose[arch]['image'] = newest_compose.group(0)
            else:
                print('Nothing to update.')
            print('')

    # Save the possibly modified variables images file
    tmp_variables_file = tempfile.NamedTemporaryFile(mode='w')
    print('---', file=tmp_variables_file)
    Y.dump(composes, tmp_variables_file)
    shutil.copy(tmp_variables_file.name, variables_images_filepath)


def main() -> None:
    available_images = get_available_images()

    for variables_images_filepath in VARIABLES_IMAGES_FILEPATHS:
        print('Updating file "{}"...'.format(variables_images_filepath))
        update_variables_images_file(variables_images_filepath, available_images)


if __name__ == '__main__':
    main()
