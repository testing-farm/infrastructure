#!/usr/bin/env python

import requests
import re
import ruamel.yaml
import shutil
import tempfile
import glob
import rich

from typing import Optional

VARIABLES_IMAGES_FILEPATHS = glob.glob('terraform/environments/*/config/variables_images.yaml') + glob.glob('terragrunt/environments/*/artemis/config/variables_images.yaml')
ARCHES = ['x86_64', 'aarch64']
ARTEMIS_URL = 'http://artemis.production.testing-farm.io/current/'

Y = ruamel.yaml.YAML()
Y.indent(sequence=2, mapping=2, offset=2)


def get_available_images() -> list[str]:
    return requests.get('{}_cache/pools/fedora-aws-x86_64/image-info'.format(ARTEMIS_URL)).json()


def check_sanity(image: str, available_images: list[str]) -> bool:
    if image in available_images:
        return True
    return False


def update_image(image_name: str, available_images: list[str]) -> Optional[str]:
    # Construct a regex from the current image to match possible candidates with newer date, e.g.
    # 'Fedora-Cloud-Base-37-20230803.0.x86_64-hvm-us-east-2-gp3-0' ->
    # 'Fedora-Cloud-Base-37-(\d{8}).0.x86_64-hvm-us-east-2-gp3-0'
    image_regex = re.sub(r'\d{8}(?:.n)?', r'(\\d{8}(?:.n)?)', image_name)

    if image_name == image_regex:
        print('    ⬅️  No "YYYYMMDD" pattern found in image {}, skipping update...'.format(image_name))
        if check_sanity(image_name, available_images):
            print('    ✅ Image "{}" is verified to be available.'.format(image_name))
        else:
            rich.print('    ⛔️ [red]Image "{}" is unavailable. '
                       'Please investigate and fix manually.[/red]'.format(image_name))
        return None

    # Match all candidates of the same image with different dates
    matched_images = []
    for available_image in available_images:
        if match := re.fullmatch(image_regex, available_image):
            matched_images.append(match)

    # Find the newest one
    newest_image = None
    for match in matched_images:
        if not newest_image or match.group(1) > newest_image.group(1):
            newest_image = match

    # If the newest one differs from the current one, bump it
    if newest_image and newest_image.group(0) != image_name:
        print('    📤 Bumped "{}"'.format(image_name))
        print('    📥     to "{}".'.format(newest_image.group(0)))
        return newest_image.group(0)
    else:
        if check_sanity(image_name, available_images):
            print('    ✅ Nothing to update for "{}". The image is verified to be available.'.format(image_name))
        else:
            rich.print('    ⛔️ [red]Nothing to update for "{}". '
                       'The image is unavailable, please investigate and fix manually.[/red]'.format(image_name))


def update_variables_images_file(variables_images_filepath: str, available_images: list[str]) -> None:
    print('📂 Processing file "{}"...'.format(variables_images_filepath))
    with open(variables_images_filepath, 'r') as f:
        composes = Y.load(f)

    for compose in composes['composes'].values():
        print('  🔎 Updating compose "{}"...'.format(compose['compose']))
        for arch in ARCHES:
            if updated_image := update_image(compose[arch]['image'], available_images):
                compose[arch]['image'] = updated_image

    # Save the possibly modified variables images file
    print('💾 Saving file "{}".'.format(variables_images_filepath))
    tmp_variables_file = tempfile.NamedTemporaryFile(mode='w')
    print('---', file=tmp_variables_file)
    Y.dump(composes, tmp_variables_file)
    shutil.copy(tmp_variables_file.name, variables_images_filepath)


def main() -> None:
    available_images = get_available_images()
    for variables_images_filepath in VARIABLES_IMAGES_FILEPATHS:
        update_variables_images_file(variables_images_filepath, available_images)


if __name__ == '__main__':
    main()
