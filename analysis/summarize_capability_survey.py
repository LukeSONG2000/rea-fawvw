#!/usr/bin/env python3
"""Summarize a local capability survey without exporting credentials or identifiers."""
import argparse
import collections
import json
import re
from pathlib import Path
import plistlib
import xml.etree.ElementTree as ET

def local(name):
    return name.rsplit('}', 1)[-1].split(':')[-1]

def clean_error(text):
    text = re.sub(r'\b[A-HJ-NPR-Z0-9]{17}\b', '<VIN>', str(text))
    text = re.sub(r'\b[0-9a-fA-F]{8}(?:-[0-9a-fA-F]+){4}\b', '<id>', text)
    return text[:1200]

def rights(path):
    root = ET.parse(path).getroot()
    attrs = {local(k): v for k, v in root.attrib.items()}
    services = {}
    for node in root:
        sid, ops = None, []
        for item in node.iter():
            a = {local(k): v for k, v in item.attrib.items()}
            if local(item.tag) == 'serviceInfo':
                sid = a.get('serviceId')
            elif local(item.tag) == 'operation' and a.get('id'):
                ops.append(a['id'])
        if sid:
            services[sid] = sorted(set(ops))
    return {'role': attrs.get('role'), 'securityLevel': attrs.get('securityLevel'),
            'status': attrs.get('status'), 'services': services}

def signal_schema(path):
    records = []
    for field in ET.parse(path).getroot().iter():
        if local(field.tag) != 'field':
            continue
        values = {local(c.tag): c.text for c in field}
        records.append({'fieldId': field.attrib.get('id'), 'textId': values.get('textId'),
                        'unit': values.get('unit'),
                        'valuePresent': values.get('value') not in (None, ''),
                        'timestampFields': sorted(k for k in field.attrib if k.startswith('ts'))})
    return records

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('private_directory', type=Path)
    parser.add_argument('--output-directory', type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    data = json.loads((args.private_directory / 'survey.json').read_text())
    assert data['state'] == 'complete' and data.get('surveyVersion') == 3
    assert data['physicalCommandsSent'] is False
    source = Path(__file__).resolve().parents[1] / 'recovered/ios-444.28.0/Payload/OneApp.app/VWCarnet-Core.bundle/warning_messages.plist'
    translations = {}
    if source.exists():
        for group in plistlib.loads(source.read_bytes()).values():
            if isinstance(group, dict):
                translations.update(group)
    summary = {'date': '2026-11-17', 'scope': 'CarNetLib current-account two-vehicle SDK and regional raw GET survey',
               'surveyVersion': 3, 'physicalCommandsSent': False, 'vehicles': []}
    schemas = {}
    for vehicle in data['vehicles']:
        index = vehicle['index']
        cp = vehicle['vehicleData'].get('carportData', {})
        name = cp.get('modelName', '')
        label = '高尔夫 GTI' if 'GTI' in name else ('探影 T-CROSS' if 'T-CROSS' in name else name)
        r = rights(args.private_directory / f'vehicle-{index}-operationList.txt')
        queries = {q['name']: q for q in vehicle['queries']}
        clean_queries = {}
        for key, q in queries.items():
            result = q.get('result')
            entry = {'state': q['state']}
            if q.get('runner'):
                entry['runner'] = q['runner']
            if q['kind'] == 'raw' and isinstance(result, dict):
                entry.update({'httpStatus': result.get('httpStatus'), 'bytes': result.get('bytes')})
            elif q['state'] == 'sdk-error' and isinstance(result, dict):
                entry['error'] = clean_error(result.get('errorMessage', result.get('errorDescription', '')))
            elif q['state'] == 'success':
                entry['emptyResult'] = result is None
                if isinstance(result, dict):
                    entry['resultClass'] = result.get('_class')
                    if 'count' in result:
                        entry['returnedCount'] = result['count']
                        entry['snapshotItemCount'] = len(result.get('items', []))
                        entry['nonNullItemFields'] = sorted({k for item in result.get('items', []) if isinstance(item, dict)
                                                           for k, value in item.items() if value is not None and k != '_class'})
                    if key == 'engineHistory':
                        entry['historyCount'] = result.get('actions', {}).get('count')
                    if key == 'healthWarnings':
                        warnings = result.get('warnings', {})
                        entry['warningCount'] = warnings.get('count')
                        entry['warnings'] = [{'textId': x.get('textId'), 'text': translations.get(x.get('textId'))}
                                             for x in warnings.get('items', [])]
                    if key == 'honkFlashConfiguration':
                        entry['configuration'] = {k: v for k, v in result.items() if k != '_class'}
                    if key == 'vehicleStatus':
                        entry['availableFields'] = sorted(k for k, v in result.items() if v is not None and k != '_class')
            clean_queries[key] = entry
        controls = {}
        specs = [('lock', 'lockUnlockFeature', 'lockSupported', 'rlu_v1', 'LOCK'),
                 ('unlock', 'lockUnlockFeature', 'unlockSupported', 'rlu_v1', 'UNLOCK'),
                 ('windowOpen', 'lockUnlockFeature', 'windowSunroofOpenSupported', 'rlu_v1', 'WINDOWSUNROOFOPEN'),
                 ('windowClose', 'lockUnlockFeature', 'windowSunroofCloseSupported', 'rlu_v1', 'WINDOWSUNROOFCLOSE'),
                 ('windowVenting', 'lockUnlockFeature', 'windowSunroofVentingOpenSupported', 'rlu_v1', 'WINDOWSUNROOFVENTINGOPEN'),
                 ('engineStart', 'remoteStartFeature', 'startActionSupported', 'rstart_v1', 'START_ACTION'),
                 ('engineStop', 'remoteStartFeature', 'stopActionSupported', 'rstart_v1', 'STOP_ACTION'),
                 ('honkFlash', 'honkFlashFeature', 'serviceEnabled', 'rhonk_v1', 'P_VREQ')]
        for key, feature, flag, service, operation in specs:
            f = vehicle['features'].get(feature) or {}
            controls[key] = {'sdkServiceEnabled': bool(f.get('serviceEnabled')), 'sdkFlag': bool(f.get(flag)),
                             'backendPermission': operation in r['services'].get(service, []),
                             'physicalExecutionTested': False}
        fields = signal_schema(args.private_directory / f'vehicle-{index}-statusReport.txt')
        schemas[label] = fields
        summary['vehicles'].append({'name': label, 'model': {k: v for k, v in cp.items() if k != '_class'},
                                    'region': vehicle['homeRegionResolution']['baseURI'],
                                    'rights': r, 'features': vehicle['features'], 'controls': controls,
                                    'queryCount': len(queries), 'queryStates': dict(collections.Counter(q['state'] for q in queries.values())),
                                    'queries': clean_queries, 'rawSignalCount': len(fields),
                                    'rawSignalsWithValues': sum(f['valuePresent'] for f in fields)})
    args.output_directory.mkdir(parents=True, exist_ok=True)
    for filename, document in [('vehicle-capability-matrix.json', summary), ('vehicle-raw-signal-catalog.json', schemas)]:
        (args.output_directory / filename).write_text(json.dumps(document, ensure_ascii=False, indent=2) + '\n')
    print('Saved sanitized capability matrix and raw signal schema; no VIN, coordinates, account IDs or tokens exported')

if __name__ == '__main__':
    main()
