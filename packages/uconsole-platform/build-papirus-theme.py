#!/usr/bin/env python3
"""Package an inherited Papirus theme using its shipped deeporange artwork.

Only links and theme metadata are generated; Papirus-owned files are untouched.
Aliases (e.g. folder-downloads) follow the same colored artwork as folder-download.
"""
from pathlib import Path
import sys


def build(icons, output):
    sections = []
    for size in (22, 24, 32, 48, 64):
        relative = f"{size}x{size}/places"
        source = icons / "Papirus" / relative
        colors = {}
        links = {}
        for colored in sorted(source.glob("*-deeporange*.svg")):
            if not colored.name.startswith(("folder-deeporange", "user-deeporange")):
                continue
            neutral = colored.name.replace("-deeporange", "", 1)
            links[neutral] = colored
            if (source / neutral).exists():
                colors[(source / neutral).resolve()] = colored
        if not links:
            raise ValueError(f"Missing Papirus deeporange icons: {source}")
        for alias in source.glob("*.svg"):
            if alias.is_symlink() and alias.resolve() in colors:
                links[alias.name] = colors[alias.resolve()]
        target = output / relative
        target.mkdir(parents=True, exist_ok=True)
        for name, colored in links.items():
            # Installed absolute path, not a build-root path.
            (target / name).symlink_to(Path("/usr/share/icons/Papirus") / relative / colored.name)
        sections.append(f"[{relative}]\nSize={size}\nContext=Places\nType=Fixed\n")
    directories = ",".join(f"{size}x{size}/places" for size in (22, 24, 32, 48, 64))
    (output / "index.theme").write_text(
        "[Icon Theme]\nName=Papirus Dark Deeporange\n"
        "Comment=Papirus Dark with deeporange folders\n"
        "Inherits=Papirus-Dark\nExample=folder\n"
        f"Directories={directories}\n\n" + "\n".join(sections)
    )


if __name__ == "__main__":
    build(Path(sys.argv[1]), Path(sys.argv[2]))
