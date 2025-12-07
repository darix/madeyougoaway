#!py
#
# madeyougoaway
#
# Copyright (C) 2025   darix
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

from salt.exceptions import SaltConfigurationError, SaltRenderError
import logging
log = logging.getLogger("madeyougoaway")

nftables_includes_dir = '/etc/nftables/includes'

def _includes_path(include_section):
  return f"{nftables_includes_dir}/{include_section}.conf"

def _indent_lines(lines, indent=0):
  if indent > 0:
    indent_str = "  " * indent
    lines = [f"{indent_str}{line}" for line in lines]
  return lines

def _render_includes(item_data, indent=0):
  return _indent_lines([f"include \"{_includes_path(include_section)}\"" for include_section in item_data], indent)

def _render_sets(item_data, indent=0):
  lines = []
  for set_name, set_data in item_data.items():
    lines.append(f"set {set_name} {{")
    if 'type' in set_data:
      lines.append(f"  type {set_data['type']};")
    if 'typeof' in set_data:
      lines.append(f"  typeof {set_data['typeof']}")
    lines.append(f"  flags {set_data['flags']};")
    lines.append( "  elements {")
    for element in set_data.get('elements', []):
      lines.append(f"    {element},")
    if 'element_mine_match' in set_data and 'element_mine_function' in set_data:
      tgttype = set_data.get('element_mine_tgttype', 'compound')
      for minion_id, mine_data in __salt__['mine.get'](set_data['element_mine_match'], set_data['element_mine_function'],tgt_type=tgttype).items():
        lines.append(f"    # {minion_id}")
        for address in mine_data:
          lines.append(f"    {address},")
    lines.append( "  }")
    lines.append( "}")
  return _indent_lines(lines, indent)

def _render_chains(item_data, indent=0):
  lines = []
  for chain_name, chain_data in item_data.items():
    lines.append(  f"chain {chain_name} {{")
    if 'type' in chain_data:
      lines.append(f"  type {chain_data['type']};")
    if 'policy' in chain_data:
      lines.append(f"  policy {chain_data['policy']};")
    rules = chain_data.get('rules', [])
    if isinstance(rules, list):
      lines.extend(_indent_lines([f"{rule};" for rule in rules], 1))
    elif isinstance(rules, str):
      lines.append(rules)
    else:
      raise SaltConfigurationError(f"Unhandled type {type(rules)} for rule list")
    lines.append(   "}")
  return _indent_lines(lines, indent)

def _render_tables(item_data, indent=0):
  lines = []
  sub_indent = indent+1
  for table_scope, scope_data in item_data.items():
    for table_type, table_data in scope_data.items():
      lines.append(f"table {table_scope} {table_type} {{")
      for sub_item_type, sub_item_data in table_data.items():
        match sub_item_type:
          case 'sets':
            lines.extend(_render_sets(sub_item_data, sub_indent))
          case 'includes':
            lines.extend(_render_includes(sub_item_data, sub_indent))
          case 'chains':
            lines.extend(_render_chains(sub_item_data, sub_indent))
          case _:
            raise SaltConfiguration(f"No idea how to handle item type {item_type}")
      lines.append( "}")
  return _indent_lines(lines, indent)

def _generate_content(pillar_path, header_content=[]):
  lines = header_content.copy()
  lines.append("# This is salt managed.")
  config_content = __salt__['pillar.get'](pillar_path, {})
  for item_type, item_data in config_content.items():
    log.error(f"item type: {item_type} data: {item_data}")
    match item_type:
      case 'sets':
        lines.extend(_render_sets(item_data))
      case 'includes':
        lines.extend(_render_includes(item_data))
      case 'tables':
        lines.extend(_render_tables(item_data))
      case _:
        raise SaltConfiguration(f"No idea how to handle item type {item_type}")
  return "\n".join(lines)


def run():
  config = {}
  nftables_pillar = __salt__['pillar.get']('nftables', {})

  nftables_packages = ['nftables-service']
  nftables_service_main_config = '/etc/nftables.conf'
  nftables_service_early_config = '/etc/nftables-early.conf'
  nftables_service_auto_config = '/var/lib/nftables/auto.conf'

  nftables_full_service  = 'nftables-full.service'
  nftables_early_service = 'nftables-early.service'

  if len(nftables_pillar) > 0 and nftables_pillar.get('enabled', True):
    config["nftables_packages"] = {
      'pkg.installed': [
        {'pkgs': nftables_packages}
      ]
    }

    if nftables_pillar.get('enabled', False):
      config['nftables_prepare_autosave_file'] = {
        'file.managed': [
          {'name':   nftables_service_auto_config },
          {'user':  'root'},
          {'group': 'root'},
          {'mode':  '0644'},
          {'require_in': ['nftables_service']},
        ]
      }

    config["nftables_includes_dir"] = {
      'file.directory': [
        {'name': nftables_includes_dir},
        {'user':  'root'},
        {'group': 'root'},
        {'mode':  '0755'},
        {'require': ["nftables_packages"]},
      ]
    }

    includes_deps_in = ["nftables_config"]
    if 'early_config' in nftables_pillar:
      includes_deps_in.append("nftables_early_config")

    for include_section, include_data in nftables_pillar.get('includes', {}).items():
      config["nftables_early_config"] = {
        'file.managed': [
          {'name': _includes_path(include_section) },
          {'user':  'root'},
          {'group': 'root'},
          {'mode':  '0644'},
          {'require': ["nftables_includes_dir"]},
          {'require_in': includes_deps_in},
          {'contents': _generate_content(pillar_path=f'nftables:includes:{include_section}')},
        ]
      }

    if 'early_config' in nftables_pillar:
      config["nftables_early_config"] = {
        'file.managed': [
          {'name': nftables_service_early_config },
          {'user':  'root'},
          {'group': 'root'},
          {'mode':  '0644'},
          {'require_in': ['nftables_early_service']},
          {'contents': _generate_content(pillar_path='nftables:early_config', header_content = ['#!/usr/sbin/nft -f'])},
        ]
      }

      config["nftables_early_service"] = {
        'service.enabled': [
          {'name': nftables_early_service},
          {'enable': True},
        ]
      }

    config["nftables_config"] = {
      'file.managed': [
        {'name': nftables_service_main_config },
        {'user':  'root'},
        {'group': 'root'},
        {'mode':  '0644'},
        {'require_in': ['nftables_service']},
        {'contents': _generate_content(pillar_path='nftables:config', header_content = ['#!/usr/sbin/nft -f'])},
      ]
    }

    config["nftables_service"] = {
      f'service.{nftables_pillar.get("service_state", "running")}': [
        {'name': nftables_full_service},
        {'enable': True},
      ]
    }
  else:
    config["nftables_service"] = {
      'service.disabled': [
        {'name': nftables_full_service},
        {'enable': False},
        {'require_in': ["nftables_config"]},
      ]
    }

    config["nftables_early_service"] = {
      'service.disabled': [
        {'name': nftables_early_service},
        {'enable': False},
        {'require_in': ["nftables_early_config"]},
      ]
    }

    config["nftables_early_config"] = {
      'file.absent': [
        {'name': nftables_service_early_config },
        {'require_in': ["nftables_packages"]},
      ]
    }

    config["nftables_config"] = {
      'file.absent': [
        {'name': nftables_service_main_config },
        {'require_in': ["nftables_packages"]},
      ]
    }

    for include_section in nftables_pillar.get('includes', []):
      config["nftables_early_config"] = {
        'file.absent': [
          {'name': _includes_path(include_section)},
          {'require_in': ["nftables_includes_dir"]},
        ]
      }

    config["nftables_includes_dir"] = {
      'file.absent': [
        {'name': nftables_includes_dir},
        {'require_in': ["nftables_packages"]},
      ]
    }

    config["nftables_packages"] = {
      'pkg.purged': [
        {'pkgs': nftables_packages}
      ]
    }

  return config