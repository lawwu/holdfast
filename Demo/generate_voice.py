#!/usr/bin/env python3
"""Generate reviewed narration with ElevenLabs; credentials never enter assets or logs."""
import argparse, base64, hashlib, json, math, os, re, shlex, subprocess, urllib.request
from pathlib import Path
ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--from-zshrc', action='store_true', help='Read a literal ELEVENLABS_API_KEY assignment without executing the shell configuration')
args = parser.parse_args()
key = os.environ.get('ELEVENLABS_API_KEY')
if not key and args.from_zshrc:
    match = re.search(r'^\s*(?:export\s+)?ELEVENLABS_API_KEY\s*=\s*(.+)$', (Path.home()/'.zshrc').read_text(), re.M)
    if match:
        parts = shlex.split(match[1], comments=True)
        if len(parts) == 1 and not any(c in parts[0] for c in '$`'): key = parts[0]
if not key: raise SystemExit('Set ELEVENLABS_API_KEY in the environment.')
voice = 'SAz9YHcvj6GT2YYXdXww'  # River, a premade voice; no voice cloning.
assets = ROOT/'public'; assets.mkdir(exist_ok=True)
scenes = json.loads((ROOT/'scenes.json').read_text())
timeline, captions = [], []
frame = 0
for scene in scenes:
    name = scene['id']; text = scene['narration']
    body = dict(text=text, model_id='eleven_multilingual_v2', voice_settings=dict(stability=0.5, similarity_boost=0.75, style=0.2, speed=1.0))
    digest = hashlib.sha256(json.dumps(body, sort_keys=True).encode()).hexdigest()
    metadata = assets/(name+'.json'); audio = assets/(name+'.mp3')
    cached = json.loads(metadata.read_text()) if metadata.exists() else {}
    if cached.get('digest') != digest or not audio.exists():
        request = urllib.request.Request(f'https://api.elevenlabs.io/v1/text-to-speech/{voice}/with-timestamps?output_format=mp3_44100_128', data=json.dumps(body).encode(), headers={'xi-api-key':key, 'Content-Type':'application/json'})
        try:
            with urllib.request.urlopen(request, timeout=90) as response: result = json.load(response)
        except Exception as error:
            raise SystemExit(f'Voice generation failed for {name}: {type(error).__name__}') from None
        audio.write_bytes(base64.b64decode(result['audio_base64']))
        cached = {'digest':digest, 'alignment':result.get('normalized_alignment') or result['alignment']}
        metadata.write_text(json.dumps(cached))
    duration = float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','default=noprint_wrappers=1:nokey=1',str(audio)],text=True))
    frames = math.ceil((duration+0.8)*30)
    alignment = cached['alignment']
    chars = alignment['characters']; starts = alignment['character_start_times_seconds']; ends = alignment['character_end_times_seconds']
    # Sentence fragments at word boundaries, under 82 characters, using actual speech timing.
    begin = 0
    for i, char in enumerate(chars):
        boundary = char in '.!?' or (char == ' ' and i-begin >= 64) or i == len(chars)-1
        if boundary:
            phrase = ''.join(chars[begin:i+1]).strip()
            if phrase:
                captions.append({'text':phrase,'startMs':round((frame/30+0.3+starts[begin])*1000),'endMs':round((frame/30+0.3+ends[i])*1000),'timestampMs':None,'confidence':None})
            begin=i+1
    timeline.append({**scene,'from':frame,'durationInFrames':frames,'audio':name+'.mp3'})
    frame += frames
    print(f'{name}: {duration:.1f}s', flush=True)
(assets/'timeline.json').write_text(json.dumps({'scenes':timeline,'captions':captions,'durationInFrames':frame},indent=2)+'\n')
def timestamp(ms):
    h,rest=divmod(ms,3600000);m,rest=divmod(rest,60000);s,milli=divmod(rest,1000)
    return f'{h:02}:{m:02}:{s:02}.{milli:03}'
vtt='WEBVTT\n\n'+'\n\n'.join(f'{timestamp(c["startMs"])} --> {timestamp(c["endMs"])}\n{c["text"]}' for c in captions)+'\n'
(assets/'holdfast-tour.vtt').write_text(vtt)
print(f'Total: {frame/30:.1f}s; {len(captions)} caption cues')
