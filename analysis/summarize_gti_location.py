"""从本机私密定位探针导出不含坐标、地址及凭据的证据。"""
import argparse
import datetime as dt
import json
import math
from pathlib import Path
from urllib.parse import urlsplit


def local_time(value):
    if not isinstance(value, (int, float)):
        return value
    if value > 100_000_000_000:
        value /= 1000
    return dt.datetime.fromtimestamp(value, dt.timezone(dt.timedelta(hours=8))).isoformat()


def distance(a, b):
    lat1, lon1, lat2, lon2 = map(math.radians, (*a, *b))
    h = math.sin((lat2-lat1)/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin((lon2-lon1)/2)**2
    return round(6371000*2*math.asin(min(1, math.sqrt(h))), 3)


def summarize(root):
    events = json.loads((root / 'events.json').read_text())
    requests = {e['key']: e for e in events if e.get('event') == 'request'}
    metrics = {e['key']: e['transactions'] for e in events if e.get('event') == 'network-metrics'}
    independent = {e['key'] for e in events if e.get('event') == 'independent-network-check'}
    responses = {e['key']: e for e in events if e.get('event') in ('response', 'delegate-complete')}
    markers = [e for e in events if e.get('event') == 'vehicle-marker']
    output = {'gnss': [], 'reverseGeocoding': [], 'vehicleMarkerCount': len(markers)}
    for key, request in requests.items():
        url = urlsplit(request['url'])
        is_gnss = url.path.endswith('/getLastGnss')
        is_geo = url.path.endswith('/geocode/regeo')
        if not (is_gnss or is_geo):
            continue
        response = responses.get(key, {})
        body = {}
        if response.get('bodyFile'):
            try:
                body = json.loads((root / response['bodyFile']).read_bytes())
            except (ValueError, OSError):
                pass
        row = {'host': url.hostname, 'path': url.path, 'method': request['method'],
               'requestTime': local_time(request.get('time')), 'cachePolicy': request.get('cachePolicy'),
               'httpStatus': response.get('status'), 'responseBytes': response.get('bytes'),
               'transportError': response.get('error', '')}
        if key in metrics:
            row['networkLoad'] = any(t.get('networkLoad') for t in metrics[key])
            row['localCache'] = any(t.get('localCache') for t in metrics[key])
        if is_gnss:
            row['independentEphemeralSession'] = key in independent
            row['code'] = body.get('code')
            data = body.get('data') or {}
            row['dataFields'] = sorted(data) if isinstance(data, dict) else []
            row['vehicleUpdateTime'] = local_time(data.get('updateTime'))
            try:
                coords = float(data['latitude']), float(data['longitude'])
                matches = [distance(coords, (float(m['latitude']), float(m['longitude']))) for m in markers]
                row['nearestVehicleMarkerDistanceMeters'] = min(matches) if matches else None
                row['coordinateReturned'] = True
            except (KeyError, ValueError, TypeError):
                row['coordinateReturned'] = False
            output['gnss'].append(row)
        else:
            # 不导出 regeocode、请求表单、key/scode 或 location。
            row['status'] = body.get('status')
            row['info'] = body.get('info')
            row['infocode'] = body.get('infocode')
            row['addressReturned'] = bool((body.get('regeocode') or {}).get('formatted_address'))
            output['reverseGeocoding'].append(row)
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = json.dumps(summarize(args.capture), ensure_ascii=False, indent=2)
    if args.output:
        args.output.write_text(result + '\n')
    else:
        print(result)
