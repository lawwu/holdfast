"""Freeze provisional labels before inference; generate a human review sheet."""
import hashlib
import html
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[2]

NEW = [
    ('home/sump-pump.md', 'Basement sump pump', 'The basement sump pump stopped starting after the storm. The plumber diagnosed a stuck float switch. Keep the service report with this equipment history.',
     'home/sump-pump-service.md', 'Sump pump service report', 'Service follow-up for the basement sump pump: replaced the stuck float switch and tested automatic operation. The pump now starts normally.', True, 'same appliance and repair follow-up'),
    ('life/cove-trip-plan.md', 'Cove camping plan', 'Our upcoming weekend at Cove Campground is for the spring bird count. We chose the north loop, bringing the green tent. The campsite confirmation belongs with this trip.',
     'life/cove-trip-booking.md', 'Cove campsite confirmation', 'Confirmation for our spring bird-count weekend at Cove Campground. The north-loop campsite is reserved for the family and the green tent.', True, 'booking for the specific planned trip'),
    ('finance/roof-policy.md', 'Home roof insurance coverage', 'The homeowners policy covers storm damage to the main home roof after the deductible. The roof claim from the autumn hailstorm is still open.',
     'finance/roof-claim.md', 'Autumn roof claim follow-up', 'The adjuster inspected hail damage on the main home roof for the open homeowners claim. Next action: send the roofer estimate under our existing coverage.', True, 'same policy and active claim'),
    ('career/office-decision.md', 'Office relocation decision', 'Decision: move the design team to the east office after the lease ends. Facilities will confirm the access-card plan before we announce the move.',
     'career/office-followup.md', 'East office access follow-up', 'Facilities confirmed the access-card plan for the design team relocation to the east office. This completes the prerequisite in our relocation decision.', True, 'follow-up resolves a specific decision prerequisite'),
    ('life/lentil-recipe.md', 'Smoky lentil soup', 'Our smoky lentil soup recipe uses red lentils, smoked paprika, carrots, and lemon. The first attempt was too thick; record the next kitchen test separately.',
     'life/lentil-recipe-test.md', 'Smoky lentil soup kitchen test', 'Follow-up to our smoky lentil soup recipe: use more stock and add lemon after cooking. The red lentils and smoked paprika stay unchanged. The thinner texture worked.', True, 'test adjusts the specific recipe'),
    ('finance/personal-savings.md', 'Harbor Bank personal savings', 'Personal emergency savings at Harbor Bank. Keep the family emergency fund separate from any business finances. This note tracks only the savings account.',
     'finance/business-card.md', 'Harbor Bank business credit card', 'Business credit card issued by Harbor Bank. Used only for studio materials and reimbursed by the studio. No shared balances or transfers with personal savings.', False, 'same provider but unrelated accounts'),
    ('life/cove-summer.md', 'Cove summer reunion', 'The family reunion at Cove Campground was a completed summer trip. The group used the south loop and the old blue tent. All planning and payments are closed.',
     'life/cove-winter.md', 'Cove winter photography trip', 'A separate solo winter photography trip to Cove Campground is being considered. No family reunion is involved. It has its own budget and lodging choices.', False, 'same place but different trips'),
]


def prepare(out):
    fixture = out / 'fixture'
    fixture.mkdir(parents=True)
    old = json.loads((ROOT / 'eval/household/crosslink.json').read_text())
    cases = []
    excluded = []
    for row in old:
        if any(row[key].startswith(('private/', 'confidential/')) for key in ['a', 'b']):
            excluded.append(row)
            continue
        for key in ['a', 'b']:
            dest = fixture / row[key]
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / 'eval/household/vault' / row[key], dest)
        cases.append({**row, 'labelSource': 'existing repository label; human review unconfirmed'})
    for a, title_a, body_a, b, title_b, body_b, link, why in NEW:
        for name, title, body in [(a, title_a, body_a), (b, title_b, body_b)]:
            dest = fixture / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(f'# {title}\n\n{body}\n')
        cases.append({'a': a, 'b': b, 'link': link, 'why': why,
                      'labelSource': 'assistant-authored provisional label; awaits human review'})
    for i, case in enumerate(cases):
        case['id'] = f'c{i+1:02}'
    assert len(cases) == 16 and sum(c['link'] for c in cases) == 8
    (out / 'cases.json').write_text(json.dumps(cases, indent=2) + '\n')
    (out / 'excluded-private-labels.json').write_text(json.dumps(excluded, indent=2) + '\n')
    hashes = {str(p.relative_to(fixture)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in sorted(fixture.rglob('*.md'))}
    (out / 'fixture-hashes.json').write_text(json.dumps(hashes, indent=2) + '\n')
    blocks = []
    for case in cases:
        notes = ''.join(f'<article><h3>{html.escape(case[k])}</h3><pre>{html.escape((fixture / case[k]).read_text())}</pre></article>' for k in ['a', 'b'])
        blocks.append(f'<section id="{case["id"]}"><h2>{case["id"]}: proposed {"LINK" if case["link"] else "NO LINK"}</h2><p>{html.escape(case["why"])} · {html.escape(case["labelSource"])}</p><div class="pair">{notes}</div></section>')
    (out / 'label-review.html').write_text('''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Cross-link label review</title><style>body{font:16px/1.55 system-ui;background:#f5f4ee;color:#20372b;max-width:1100px;margin:40px auto;padding:0 20px}section{border-top:1px solid #b8c8bb;margin-top:35px;padding-top:20px}.pair{display:grid;grid-template-columns:1fr 1fr;gap:20px}article{background:#fff;padding:18px;min-width:0}pre{white-space:pre-wrap;overflow-wrap:anywhere;font:14px/1.6 system-ui}h3{overflow-wrap:anywhere;font-size:15px}@media(max-width:700px){.pair{grid-template-columns:1fr}}@media(prefers-color-scheme:dark){body{background:#19221c;color:#e0eee3}article{background:#26352b}}</style><h1>Review the ground-truth labels</h1><p>All notes are synthetic. These labels are provisional. Review each pair independently of the model results. Report corrections by case ID; accepting them records a human review, not new model evidence.</p><p>The judge sees the first 1,500 characters of each note body plus its title/path; the full notes below help check whether that excerpt is adequate.</p>''' + ''.join(blocks) + '</html>')
    return cases
