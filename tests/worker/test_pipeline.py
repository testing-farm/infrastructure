import os
import pytest

from pytest_gluetool import CitoolRunnerType
from pytest_gluetool.scenario import run_scenario, load_scenarios, Scenario

from typing import Any, Tuple


@pytest.mark.parametrize(
    'scenario, scenario_name',
    [
        *load_scenarios('tests/worker/public', base_scenarios_dir_path='tests/worker/base-scenarios'),
        *load_scenarios('tests/worker/redhat/pipeline', base_scenarios_dir_path='tests/worker/base-scenarios')
    ]
)
def test_pipeline(
    citool: Tuple[CitoolRunnerType, str], variables: dict[str, Any], scenario: Scenario, scenario_name: str
) -> None:
    # Create a transform function when running in GitLab CI
    # NOTE(mvadkert): GitLab actually has two kind of URLs for artifacts, one for files and the other for directories:
    # https://testing-farm.gitlab.io/-/gluetool-modules/-/jobs/11512494224/artifacts/infrastructure/.pytest/popen-gw13/test_pipeline_tests_worker_pub0/citool-debug.txt
    # https://gitlab.com/testing-farm/gluetool-modules/-/jobs/11512494224/artifacts/browse/infrastructure/.pytest/popen-gw13/test_pipeline_tests_worker_pub0
    if 'CI_ARTIFACT_URL_PREFIX_FILE' in os.environ and 'CI_ARTIFACT_URL_PREFIX_DIR' in os.environ:
        artifact_url_prefix_file = os.environ['CI_ARTIFACT_URL_PREFIX_FILE']
        artifact_url_prefix_dir = os.environ['CI_ARTIFACT_URL_PREFIX_DIR']

        def transform_artifact_path(path: str) -> str:
            if os.path.isdir(path):
                return '{}/{}'.format(artifact_url_prefix_dir, os.path.relpath(path, start=os.curdir))
            return '{}/{}'.format(artifact_url_prefix_file, os.path.relpath(path, start=os.curdir))

        run_scenario(citool, variables, scenario, scenario_name, 'pipeline', transform_artifact_path)

    else:
        run_scenario(citool, variables, scenario, scenario_name, 'pipeline')
