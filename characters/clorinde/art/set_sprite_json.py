"""Replaces the "sprite" block of characters/clorinde/character.json with a generated one.

    python set_sprite_json.py <sprite.json> <character.json>
"""
import json
import sys


def block(spec):
    head = {k: v for k, v in spec.items() if k != "animations"}
    lines = ['  "sprite": {' + json.dumps(head)[1:-1] + ',', '    "animations": {']
    items = list(spec["animations"].items())
    for i, (name, a) in enumerate(items):
        end = "," if i < len(items) - 1 else ""
        if isinstance(a, list):
            lines.append(f'      "{name}": [')
            for j, v in enumerate(a):
                lines.append("        " + json.dumps(v) + ("," if j < len(a) - 1 else ""))
            lines.append("      ]" + end)
        else:
            lines.append(f'      "{name}": ' + json.dumps(a) + end)
    lines += ["    }", "  },"]
    return "\n".join(lines)


def main(sprite_path, char_path):
    with open(sprite_path) as fh:
        spec = json.load(fh)
    text = open(char_path, encoding="utf-8").read()
    start = text.index('  "sprite": {')
    depth, i = 0, text.index("{", start)
    while True:
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                break
        i += 1
    end = i + 1
    if text[end] == ",":
        end += 1
    text = text[:start] + block(spec) + text[end:]
    json.loads(text)
    open(char_path, "w", encoding="utf-8").write(text)
    print("updated", char_path)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
