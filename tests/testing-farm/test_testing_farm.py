from typing import Any

import pytest

from pytest_gluetool.scenario import Scenario, load_scenarios, run_testing_farm_scenario


@pytest.mark.parametrize(
    'scenario, scenario_name',
    load_scenarios('tests/testing-farm/redhat', base_scenarios_dir_path='tests/testing-farm/base-scenarios'),
)
def test_testing_farm(
    variables: dict[str, Any],
    extra_testing_farm_args: list[str],
    scenario: Scenario,
    scenario_name: str,
) -> None:
    run_testing_farm_scenario(variables, scenario, scenario_name, extra_testing_farm_args)
