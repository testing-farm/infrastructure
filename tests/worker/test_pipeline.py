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
    if 'CI_ARTIFACT_URL_PREFIX' in os.environ:
        artifact_url_prefix = os.environ['CI_ARTIFACT_URL_PREFIX']

        def transform_artifact_path(path: str) -> str:
            return '{}/{}'.format(artifact_url_prefix, os.path.relpath(path, start=os.curdir))

        run_scenario(citool, variables, scenario, scenario_name, 'pipeline', transform_artifact_path)

    else:
        run_scenario(citool, variables, scenario, scenario_name, 'pipeline')
