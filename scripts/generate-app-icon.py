#!/usr/bin/env python3
"""Generate the PETVocabularyTrainer macOS app icon.

This script is dependency-light on purpose: it writes a deterministic SVG,
uses macOS Quick Look to rasterize the 1024px master PNG, then uses `sips` and
`iconutil` to build the final `.icns` bundle asset.
"""

from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESOURCE_DIR = ROOT / "Sources" / "PETVocabularyTrainer" / "Resources"
SVG_PATH = RESOURCE_DIR / "AppIcon.svg"
PNG_PATH = RESOURCE_DIR / "AppIcon.png"
ICNS_PATH = RESOURCE_DIR / "AppIcon.icns"


def require_tool(name: str) -> str:
    path = shutil.which(name)
    if not path:
        raise SystemExit(f"{name} is required to generate the app icon on macOS.")
    return path


def run(command: list[str]) -> None:
    subprocess.run(command, check=True)


def write_svg() -> None:
    RESOURCE_DIR.mkdir(parents=True, exist_ok=True)
    SVG_PATH.write_text(
        """<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <style>
      .serif { font-family: Avenir Next Condensed, Helvetica Neue, Arial, sans-serif; font-weight: 800; }
      .label { font-family: Avenir Next, Helvetica Neue, Arial, sans-serif; font-weight: 900; letter-spacing: 8px; }
    </style>
  </defs>

  <rect x="82" y="104" width="862" height="862" rx="210" fill="#393124" opacity="0.16"/>
  <rect x="64" y="56" width="896" height="896" rx="210" fill="#f8f1e7"/>
  <rect x="64" y="56" width="896" height="896" rx="210" fill="none" stroke="#ded1be" stroke-width="10"/>

  <circle cx="512" cy="512" r="334" fill="#d67b5b"/>
  <circle cx="512" cy="512" r="276" fill="none" stroke="#ffeccd" stroke-width="10" opacity="0.55"/>

  <polygon points="784,184 799,225 842,225 807,251 820,292 784,267 748,292 761,251 726,225 769,225"
           fill="#f5bf4b" stroke="#585934" stroke-width="6"/>
  <line x1="746" y1="246" x2="822" y2="246" stroke="#585934" stroke-width="7" stroke-linecap="round"/>
  <line x1="784" y1="208" x2="784" y2="284" stroke="#585934" stroke-width="7" stroke-linecap="round"/>

  <polygon points="266,406 366,158 488,430" fill="#fffaf0" stroke="#585934" stroke-width="10" stroke-linejoin="round"/>
  <polygon points="536,430 658,158 758,406" fill="#fffaf0" stroke="#585934" stroke-width="10" stroke-linejoin="round"/>
  <polygon points="322,376 374,244 438,390" fill="#eea089"/>
  <polygon points="586,390 650,244 702,376" fill="#eea089"/>

  <ellipse cx="512" cy="540" rx="280" ry="226" fill="#fffaf0" stroke="#585934" stroke-width="10"/>

  <ellipse cx="389" cy="503" rx="47" ry="45" fill="#344e7b"/>
  <ellipse cx="635" cy="503" rx="47" ry="45" fill="#344e7b"/>
  <circle cx="392" cy="495" r="17" fill="#fffaf0"/>
  <circle cx="638" cy="495" r="17" fill="#fffaf0"/>

  <polygon points="512,548 472,592 552,592" fill="#b05841"/>
  <path d="M512 590 C500 627 471 636 455 612" fill="none" stroke="#4a4942" stroke-width="8" stroke-linecap="round"/>
  <path d="M512 590 C524 627 553 636 569 612" fill="none" stroke="#4a4942" stroke-width="8" stroke-linecap="round"/>

  <line x1="272" y1="530" x2="432" y2="548" stroke="#585934" stroke-width="7" stroke-linecap="round"/>
  <line x1="272" y1="572" x2="432" y2="590" stroke="#585934" stroke-width="7" stroke-linecap="round"/>
  <line x1="272" y1="614" x2="432" y2="632" stroke="#585934" stroke-width="7" stroke-linecap="round"/>
  <line x1="592" y1="548" x2="752" y2="530" stroke="#585934" stroke-width="7" stroke-linecap="round"/>
  <line x1="592" y1="590" x2="752" y2="572" stroke="#585934" stroke-width="7" stroke-linecap="round"/>
  <line x1="592" y1="632" x2="752" y2="614" stroke="#585934" stroke-width="7" stroke-linecap="round"/>

  <rect x="316" y="708" width="392" height="130" rx="50" fill="#6c6c44" stroke="#585934" stroke-width="8"/>
  <polygon points="644,740 788,778 662,820" fill="#585934"/>
  <text x="512" y="808" text-anchor="middle" class="label" font-size="124" fill="#fffaf0">PET</text>

  <circle cx="292" cy="758" r="13" fill="#f5bf4b"/>
  <circle cx="250" cy="794" r="12" fill="#ffe8b2"/>
  <circle cx="230" cy="830" r="11" fill="#ffe8b2"/>
</svg>
""",
        encoding="utf-8",
    )


def render_png(qlmanage: str) -> None:
    with tempfile.TemporaryDirectory(prefix="pet-app-icon-") as tmp:
        temp_dir = Path(tmp)
        run([qlmanage, "-t", "-s", "1024", "-o", str(temp_dir), str(SVG_PATH)])
        quicklook_png = temp_dir / f"{SVG_PATH.name}.png"
        if not quicklook_png.exists():
            raise SystemExit(f"Quick Look did not create the expected PNG: {quicklook_png}")
        shutil.copyfile(quicklook_png, PNG_PATH)


def build_iconset(sips: str, iconutil: str) -> None:
    icon_specs = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]

    with tempfile.TemporaryDirectory(prefix="pet-app-iconset-") as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for size, filename in icon_specs:
            run([sips, "-z", str(size), str(size), str(PNG_PATH), "--out", str(iconset / filename)])

        run([iconutil, "-c", "icns", "-o", str(ICNS_PATH), str(iconset)])


def main() -> None:
    qlmanage = require_tool("qlmanage")
    sips = require_tool("sips")
    iconutil = require_tool("iconutil")

    write_svg()
    render_png(qlmanage)
    build_iconset(sips, iconutil)

    print(f"Generated {SVG_PATH}")
    print(f"Generated {PNG_PATH}")
    print(f"Generated {ICNS_PATH}")


if __name__ == "__main__":
    main()
