#!/usr/bin/env python

"""
Generate Artemis server.yaml.tftpl pool configurations from FMF definitions.

Pool definitions are stored as FMF (Flexible Metadata Format) trees under each
environment's artemis directory:

    terragrunt/environments/<env>/artemis/
    ├── config/
    │   ├── server-header.yaml.tftpl   # Static header (users, ssh-keys, etc.)
    │   └── server.yaml.tftpl          # Generated output (header + pools)
    └── pools/
        ├── .fmf/version
        ├── main.fmf                   # Root defaults (capabilities, etc.)
        └── aws/
            ├── main.fmf               # AWS driver defaults (credentials, etc.)
            ├── x86_64/
            │   ├── main.fmf           # x86_64 architecture settings
            │   └── fedora-aws-x86_64.fmf
            └── aarch64/
                ├── main.fmf           # aarch64 architecture settings
                └── fedora-aws-aarch64.fmf

FMF inheritance allows each leaf node (.fmf file without children) to inherit
settings from all parent main.fmf files. Use the '+' suffix operator
(e.g., 'capabilities+:') for additive dict merging.

The script reads each leaf node from the FMF tree, extracts pool-level keys
(driver), and renders the remaining data as pool parameters. Terraform template
expressions (${...}) are quoted, and raw template keys (security-group with
%{...} directives) are emitted as-is without YAML serialization.

Each environment (dev, staging, production) maintains its own independent FMF
tree - definitions are NOT shared between environments.
"""

import io
import os
import os.path
import sys
from typing import Any, Optional

import fmf
import ruamel.yaml
import ruamel.yaml.scalarstring
import typer


# Paths relative to the environment artemis directory
POOLS_DIR = 'pools'
CONFIG_DIR = 'config'
HEADER_FILE = 'server-header.yaml.tftpl'
OUTPUT_FILE = 'server.yaml.tftpl'

# Keys whose values contain Terraform template directives and should be emitted as raw text
RAW_TEMPLATE_KEYS = {'security-group'}

# Base directory of the repository
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# All environment paths relative to REPO_ROOT
ENVIRONMENTS = [
    'terragrunt/environments/dev/artemis',
    'terragrunt/environments/staging/artemis',
    'terragrunt/environments/production/artemis',
]

# Indentation for parameters under 'parameters:' key
PARAM_INDENT = '      '    # 6 spaces (2 for pools + 4 for parameters key)


app = typer.Typer(
    no_args_is_help=True,
    help="Generate Artemis server.yaml.tftpl pool configurations from FMF definitions.",
    rich_markup_mode="rich",
)


def _prepare_yaml(o: Any) -> Any:
    """Prepare data for YAML serialization, sorting keys and handling multiline strings."""
    if isinstance(o, dict):
        return {key: _prepare_yaml(o[key]) for key in sorted(o.keys())}

    if isinstance(o, list):
        return [_prepare_yaml(item) for item in o]

    if isinstance(o, str) and '\n' in o:
        return ruamel.yaml.scalarstring.LiteralScalarString(o)

    return o


def as_yaml(struct: Any) -> str:
    """Serialize a data structure to YAML string."""
    output = io.StringIO()

    yaml = ruamel.yaml.YAML()
    yaml.map_indent = 2
    yaml.sequence_indent = 4
    yaml.sequence_dash_offset = 2
    yaml.default_flow_style = False
    yaml.allow_unicode = True
    yaml.encoding = 'utf-8'
    yaml.width = 1000
    yaml.explicit_start = False

    struct = _prepare_yaml(struct)

    yaml.dump(struct, output)

    return output.getvalue()


def _is_terraform_template(value: Any) -> bool:
    """Check if a value contains Terraform template directives."""
    if not isinstance(value, str):
        return False
    return '%{' in value or '${' in value


def _quote_terraform_values(o: Any) -> Any:
    """Ensure Terraform template expressions in strings are properly quoted."""
    if isinstance(o, dict):
        return {key: _quote_terraform_values(val) for key, val in o.items()}

    if isinstance(o, list):
        return [_quote_terraform_values(item) for item in o]

    if isinstance(o, str) and '${' in o and '\n' not in o:
        # Single-line Terraform template expression - ensure it's quoted
        return ruamel.yaml.scalarstring.DoubleQuotedScalarString(o)

    return o


def get_poolname(node: fmf.Tree) -> str:
    """Get pool name from FMF tree node."""
    return os.path.basename(node.name)


def generate_pool_text(node: fmf.Tree) -> str:
    """Generate a pool entry as formatted text from an FMF tree node."""
    poolname = get_poolname(node)

    print(f'Generating {poolname}', file=sys.stderr)

    data = node.data.copy()

    driver = data.pop('driver', None)
    if driver is None:
        print(f'Warning: pool {poolname} has no driver defined', file=sys.stderr)
        driver = 'unknown'

    # Separate raw template keys from regular parameters
    raw_params = {}
    for key in list(data.keys()):
        if key in RAW_TEMPLATE_KEYS and _is_terraform_template(data[key]):
            raw_params[key] = data.pop(key)

    # Quote Terraform template expressions in regular parameters
    data = _quote_terraform_values(data)

    # Build pool entry text manually to control key ordering
    lines = []
    lines.append(f'  - name: {poolname}')
    lines.append(f'    driver: {driver}')
    lines.append('    parameters:')

    # Serialize regular parameters
    params_yaml = as_yaml(data).rstrip('\n')

    # Inject raw template parameters at the right position (alphabetically sorted)
    all_param_keys = sorted(list(data.keys()) + list(raw_params.keys()))

    # Re-serialize parameters in sorted order, injecting raw template values
    if raw_params:
        # We need to insert the raw template keys in sorted position
        # First, serialize the regular params as a dict
        regular_yaml_lines = params_yaml.split('\n')

        # Find where to insert each raw param
        output_param_lines = []
        regular_key_positions = {}

        # Parse the regular YAML to find TOP-LEVEL key positions only
        # (lines that start without indentation)
        for i, line in enumerate(regular_yaml_lines):
            if line and not line[0].isspace() and ':' in line:
                key = line.split(':')[0]
                regular_key_positions[key] = i

        # Interleave regular and raw params in sorted order
        used_regular_lines = set()
        for key in all_param_keys:
            if key in raw_params:
                # Emit raw template parameter
                value = raw_params[key]
                # Strip leading/trailing whitespace from the template value
                value = value.strip()
                output_param_lines.append(f'{key}:')
                for tpl_line in value.split('\n'):
                    output_param_lines.append(f'  {tpl_line}')
            elif key in regular_key_positions:
                # Find all lines belonging to this key
                start = regular_key_positions[key]
                # Find the end (next top-level key or end of lines)
                end = len(regular_yaml_lines)
                for next_key in sorted(regular_key_positions.keys()):
                    pos = regular_key_positions[next_key]
                    if pos > start and pos < end:
                        end = pos
                for i in range(start, end):
                    if i not in used_regular_lines:
                        output_param_lines.append(regular_yaml_lines[i])
                        used_regular_lines.add(i)

        params_yaml = '\n'.join(output_param_lines)

    # Indent parameters content under 'parameters:'
    for line in params_yaml.split('\n'):
        if line.strip():
            lines.append(PARAM_INDENT + line)
        else:
            lines.append('')

    return '\n'.join(lines)


def generate_pools_yaml(env_path: str) -> str:
    """Generate the pools YAML section from FMF definitions."""
    pools_path = os.path.join(env_path, POOLS_DIR)

    if not os.path.isdir(pools_path):
        print(f'Error: pools directory not found: {pools_path}', file=sys.stderr)
        raise typer.Exit(code=1)

    tree = fmf.Tree(pools_path)
    pool_texts = []

    for node in tree.prune():
        pool_text = generate_pool_text(node)
        pool_texts.append(pool_text)

    if not pool_texts:
        print('Warning: no pools found in FMF tree', file=sys.stderr)
        return ''

    return '\n\n'.join(pool_texts) + '\n'


def generate_server_yaml(env_path: str) -> str:
    """Generate the complete server.yaml.tftpl from header + pools."""
    config_path = os.path.join(env_path, CONFIG_DIR)
    header_path = os.path.join(config_path, HEADER_FILE)

    if not os.path.isfile(header_path):
        print(f'Error: header file not found: {header_path}', file=sys.stderr)
        raise typer.Exit(code=1)

    with open(header_path) as f:
        header = f.read()

    pools_yaml = generate_pools_yaml(env_path)

    # Ensure header ends with a newline
    if not header.endswith('\n'):
        header += '\n'

    return header + pools_yaml


def _resolve_env_path(env_path: str) -> str:
    """Resolve environment path to absolute path."""
    if os.path.isabs(env_path):
        return env_path
    return os.path.join(REPO_ROOT, env_path)


def process_environment(env_path: str) -> None:
    """Generate and write server.yaml.tftpl for a single environment."""
    abs_env_path = _resolve_env_path(env_path)
    output_path = os.path.join(abs_env_path, CONFIG_DIR, OUTPUT_FILE)

    server_yaml = generate_server_yaml(abs_env_path)

    with open(output_path, 'w') as f:
        f.write(server_yaml)

    print(f'Written {output_path}', file=sys.stderr)


@app.command("generate")
def cmd_generate(
    env_path: Optional[str] = typer.Argument(
        default=None,
        help="Path to the artemis environment directory (e.g., terragrunt/environments/production/artemis).",
    ),
    all_envs: bool = typer.Option(
        False, "--all",
        help="Generate for all environments (dev, staging, production).",
    ),
) -> None:
    """
    Generate server.yaml.tftpl from FMF pool definitions.
    """
    if all_envs:
        for env in ENVIRONMENTS:
            process_environment(env)
    elif env_path:
        process_environment(env_path)
    else:
        print("Error: provide an environment path or use --all", file=sys.stderr)
        raise typer.Exit(code=1)


@app.command("list-names")
def cmd_list_names(
    env_path: str = typer.Argument(
        ...,
        help="Path to the artemis environment directory.",
    ),
) -> None:
    """
    List pool names from an FMF tree.
    """
    abs_env_path = _resolve_env_path(env_path)
    pools_path = os.path.join(abs_env_path, POOLS_DIR)

    if not os.path.isdir(pools_path):
        print(f'Error: pools directory not found: {pools_path}', file=sys.stderr)
        raise typer.Exit(code=1)

    tree = fmf.Tree(pools_path)
    for node in tree.prune():
        print(get_poolname(node))


def main() -> None:
    """Main entrypoint for the script."""
    app()


if __name__ == '__main__':
    main()
