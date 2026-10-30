from typing import Any

import pytest

from pytest_gluetool.scenario import Scenario, load_scenarios, run_testing_farm_scenario


@pytest.mark.parametrize(
    'scenario, scenario_name',
    load_scenarios('tests/testing-farm/public', base_scenarios_dir_path='tests/testing-farm/base-scenarios'),
)
def test_testing_farm(
    variables: dict[str, Any],
    extra_testing_farm_args: list[str],
    scenario: Scenario,
    scenario_name: str,
) -> None:
    scenario_variables = scenario.content.get('variables', {})
    if scenario_variables.get('REQUEST_ID') == 'change-me':
        scenario_variables['REQUEST_ID'] = variables['REQUEST_ID']
    run_testing_farm_scenario(variables, scenario, scenario_name, extra_testing_farm_args)
