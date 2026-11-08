"""Display-grid logic from the guide: cell = 3.6 / cols wide x 1.85 / rows deep, one layer, no stacking.

The guide's catalog gives each product's grid and model size. `solve_grid` only fills in
products with no guide model (IronSeries Headsets, Fourth Knight), using proportions as a start.
"""
from __future__ import annotations


def grid_from_catalog(entry: dict, rules: dict, proportions) -> dict:
    spot = rules["display_spot_studs"]["value"]
    cols, rows = entry["grid"]
    pitch_x, pitch_y = spot["width"] / cols, spot["depth"] / rows
    if entry.get("dims"):
        width, depth, height = entry["dims"]
        source = "guide"
    else:
        pw, pd, ph = proportions
        scale = min((pitch_x - 0.05) / pw, (pitch_y - 0.05) / pd, 1.5 / max(pw, pd), 1.5 / ph)
        width, depth, height = pw * scale, pd * scale, ph * scale
        source = "INFERRED: no model in the guide"
    return {"cols": cols, "rows": rows, "quantity": cols * rows, "pitch": [round(pitch_x, 4), round(pitch_y, 4)],
            "width": round(width, 4), "depth": round(depth, 4), "height": round(height, 4),
            "gap": [round(pitch_x - width, 4), round(pitch_y - depth, 4)], "size_source": source}


def layer_fits(grid: dict, rules: dict) -> bool:
    """Every unit stays inside its own cell, which is how ShelfService places units."""
    return grid["width"] <= grid["pitch"][0] + 1e-6 and grid["depth"] <= grid["pitch"][1] + 1e-6
