#!/usr/bin/env python3
"""Control only the isolated HOLDFAST_DEMO_CAPTURE app; capture its own window."""
import argparse, json, subprocess, time, uuid
from pathlib import Path
root=Path(__file__).resolve().parents[1]
control=root/'build/demo/control'
p=argparse.ArgumentParser();p.add_argument('action');p.add_argument('value',nargs='?',default='');p.add_argument('--shot');p.add_argument('--window',default='Holdfast');a=p.parse_args()
if a.action != 'status':
    command={'id':str(uuid.uuid4()),'action':a.action,'value':a.value}
    temporary=control/'next.json';temporary.write_text(json.dumps(command));temporary.replace(control/'command.json')
    for _ in range(30):
        time.sleep(.2)
        if (control/'status.json').exists() and json.loads((control/'status.json').read_text()).get('command')==command['id']:break
    else:raise SystemExit('Demo app did not acknowledge the command')
state=json.loads((control/'status.json').read_text())
if a.shot:
    time.sleep(1.2)
    window=next(w for w in state['windows'] if (w['title'] != 'Settings' if a.window == 'Holdfast' else w['title'] == a.window))
    destination=root/'Demo/public'/a.shot
    subprocess.run(['screencapture','-x','-o','-l',str(window['id']),str(destination)],check=True)
print(json.dumps(state,indent=2))
