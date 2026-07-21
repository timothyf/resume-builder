#!/usr/bin/env python3

import argparse
import json
import shutil
import subprocess
from pathlib import Path

import pdfplumber
from PIL import Image, ImageChops


def parse_args():
    parser = argparse.ArgumentParser(description="Render and inspect a visual-regression PDF")
    parser.add_argument("pdf", type=Path)
    parser.add_argument("output_dir", type=Path)
    return parser.parse_args()


def nonwhite_fraction(image_path):
    with Image.open(image_path).convert("RGB") as image:
        white = Image.new("RGB", image.size, "white")
        difference = ImageChops.difference(image, white).convert("L")
        histogram = difference.histogram()
        changed_pixels = sum(histogram[4:])
        return changed_pixels / (image.width * image.height)


def main():
    args = parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    renderer = shutil.which("pdftoppm")
    if not renderer:
        raise SystemExit("pdftoppm is required for PDF visual regression checks")

    prefix = args.output_dir / "page"
    subprocess.run(
        [renderer, "-png", "-r", "110", str(args.pdf), str(prefix)],
        check=True,
        capture_output=True,
        text=True,
    )
    rendered_pages = sorted(args.output_dir.glob("page-*.png"))
    failures = []
    page_metrics = []

    with pdfplumber.open(args.pdf) as document:
        if len(document.pages) != len(rendered_pages):
            failures.append(
                f"PDF has {len(document.pages)} pages but pdftoppm rendered {len(rendered_pages)}"
            )

        for index, page in enumerate(document.pages):
            page_number = index + 1
            image_path = rendered_pages[index] if index < len(rendered_pages) else None
            text = page.extract_text() or ""
            ink_fraction = nonwhite_fraction(image_path) if image_path else 0.0
            if not text.strip() and not page.images:
                failures.append(f"page {page_number} is unexpectedly blank")
            if ink_fraction < 0.002:
                failures.append(
                    f"page {page_number} has too little rendered content ({ink_fraction:.4%})"
                )

            clipped = []
            for char in page.chars:
                if (
                    char["x0"] < -0.5
                    or char["x1"] > page.width + 0.5
                    or char["top"] < -0.5
                    or char["bottom"] > page.height + 0.5
                ):
                    clipped.append(char.get("text", "?"))
            if clipped:
                preview = "".join(clipped[:20])
                failures.append(f"page {page_number} contains clipped text: {preview!r}")

            page_metrics.append(
                {
                    "page": page_number,
                    "width": round(float(page.width), 2),
                    "height": round(float(page.height), 2),
                    "characters": len(page.chars),
                    "ink_fraction": round(ink_fraction, 6),
                }
            )

    result = {"page_count": len(rendered_pages), "pages": page_metrics}
    print(json.dumps(result, indent=2))
    if failures:
        raise SystemExit("PDF visual checks failed:\n- " + "\n- ".join(failures))


if __name__ == "__main__":
    main()
