import pytest

from pytest_gluetool import CitoolRunnerType, ScenarioType
from pytest_gluetool.scenario import run_scenario, load_scenarios

from typing import Any, Tuple


@pytest.mark.parametrize(
    'scenario, scenario_name',
    [
        *load_scenarios('tests/worker/public/pipeline', base_scenarios_dir_path='tests/worker/base-scenarios'),
        *load_scenarios('tests/worker/redhat/pipeline', base_scenarios_dir_path='tests/worker/base-scenarios')
    ]
)
def test_pipeline(
    citool: Tuple[CitoolRunnerType, str], variables: dict[str, Any], scenario: ScenarioType, scenario_name: str
) -> None:
    run_scenario(citool, variables, scenario, scenario_name, 'pipeline')
