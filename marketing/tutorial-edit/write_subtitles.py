import json
from pathlib import Path

folder = Path(__file__).resolve().parent.parent
data = json.loads((folder / 'tutorial-cuts.json').read_text(encoding='utf-8'))
def timestamp(seconds):
    return f'{seconds // 3600:02}:{seconds // 60 % 60:02}:{seconds % 60:02},000'
elapsed = 0
lines = []
for index, scene in enumerate(data['scenes']):
    end = elapsed + scene['duration']
    lines.append(f"{index + 1}\n{timestamp(elapsed)} --> {timestamp(end)}\n{scene['narration']}\n")
    elapsed = end
(folder / 'tutorial-bn.srt').write_text('\n'.join(lines), encoding='utf-8')
print(f'Subtitles: {len(lines)} chapters, {elapsed} seconds')
