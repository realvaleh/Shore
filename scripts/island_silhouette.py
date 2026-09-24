"""Housing-neck island path. Keep in lockstep with IslandMetrics.shoulderFit.

SwiftUI y-down. Used by the screenshot placeholders and the Linux scaffold check
so a T-bar or an early menu-bar flare fails without a Mac.
"""

from __future__ import annotations

NECK_COVER = 0.70
SHOULDER_BEND = 0.52
SHOULDER_RUN_MIN = 20.0
SHOULDER_RUN_MAX = 56.0
BELLY_GAP = 8.0
SQUIRCLE = 0.55


def shoulder_fit(rect, notch_w, notch_h, corner, ear):
    """rect is (x, y, w, h). Returns the same fields as IslandShoulderFit."""
    x, y, w, h = rect
    neck = min(max(notch_w, 0.0), w)
    mid = x + w / 2
    neck_left = mid - neck / 2
    neck_right = neck_left + neck
    wing = max(0.0, (w - neck) / 2)
    bottom = min(max(corner, 8.0), max(6.0, w / 2 - 1), h * 0.46)
    housing = max(0.0, notch_h)
    y_start_cap = max(8.0, h - bottom - 8)
    y_start = y + min(max(8.0, housing * NECK_COVER), y_start_cap)
    opens = wing > 1.5
    y_belly = y_start
    if opens:
        run = min(SHOULDER_RUN_MAX, max(SHOULDER_RUN_MIN, ear * 0.70 + wing * 0.34))
        target = max(y_start + run, y + housing + 4)
        y_belly = min(y + h - bottom - 4, target)
        if y_belly < y_start + 14:
            y_belly = min(y + h - bottom - 2, y_start + 14)
    return {
        "neck_left": neck_left,
        "neck_right": neck_right,
        "y_start": y_start,
        "y_belly": y_belly,
        "bottom_radius": bottom,
        "opens": opens,
        "wing": wing,
    }


def _cubic(p0, p1, p2, p3, steps=28):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        x = u**3 * p0[0] + 3 * u**2 * t * p1[0] + 3 * u * t**2 * p2[0] + t**3 * p3[0]
        y = u**3 * p0[1] + 3 * u**2 * t * p1[1] + 3 * u * t**2 * p2[1] + t**3 * p3[1]
        pts.append((x, y))
    return pts


def _corner(start, corner, end, kappa=SQUIRCLE, steps=12):
    return _cubic(
        start,
        (start[0] + (corner[0] - start[0]) * kappa, start[1] + (corner[1] - start[1]) * kappa),
        (end[0] + (corner[0] - end[0]) * kappa, end[1] + (corner[1] - end[1]) * kappa),
        end,
        steps=steps,
    )


def polygon(origin, size, notch_w, notch_h, corner, ear):
    """Closed silhouette. origin/size are the chrome rect."""
    ox, oy = origin
    w, h = size
    fit = shoulder_fit((ox, oy, w, h), notch_w, notch_h, corner, ear)
    left = ox
    right = ox + w
    bottom = oy + h
    br = fit["bottom_radius"]
    pts = [(fit["neck_left"], oy), (fit["neck_right"], oy), (fit["neck_right"], fit["y_start"])]
    if fit["opens"]:
        dy = max(0.01, fit["y_belly"] - fit["y_start"])
        bend = SHOULDER_BEND
        pts += _cubic(
            (fit["neck_right"], fit["y_start"]),
            (fit["neck_right"], fit["y_start"] + bend * dy),
            (right, fit["y_belly"] - bend * dy),
            (right, fit["y_belly"]),
        )[1:]
    pts.append((right, bottom - br))
    pts += _corner((right, bottom - br), (right, bottom), (right - br, bottom))[1:]
    pts.append((left + br, bottom))
    pts += _corner((left + br, bottom), (left, bottom), (left, bottom - br))[1:]
    side_y = fit["y_belly"] if fit["opens"] else fit["y_start"]
    pts.append((left, side_y))
    if fit["opens"]:
        dy = max(0.01, fit["y_belly"] - fit["y_start"])
        bend = SHOULDER_BEND
        pts += _cubic(
            (left, fit["y_belly"]),
            (left, fit["y_belly"] - bend * dy),
            (fit["neck_left"], fit["y_start"] + bend * dy),
            (fit["neck_left"], fit["y_start"]),
        )[1:]
    pts.append((fit["neck_left"], oy))
    return pts


def contains(points, x, y):
    """Even-odd ray cast. Points on the boundary count as inside."""
    inside = False
    n = len(points)
    for i in range(n):
        x0, y0 = points[i]
        x1, y1 = points[(i + 1) % n]
        if abs(y1 - y0) < 1e-9:
            if abs(y - y0) < 0.4 and min(x0, x1) - 0.4 <= x <= max(x0, x1) + 0.4:
                return True
            continue
        if (y0 > y) != (y1 > y):
            cross = x0 + (y - y0) * (x1 - x0) / (y1 - y0)
            if abs(cross - x) < 0.4:
                return True
            if cross > x:
                inside = not inside
    return inside


def span_at(points, y):
    """Horizontal crossings at y. None when the scan misses the silhouette."""
    xs = []
    n = len(points)
    for i in range(n):
        x0, y0 = points[i]
        x1, y1 = points[(i + 1) % n]
        if abs(y1 - y0) < 1e-9:
            continue
        if (y0 <= y < y1) or (y1 <= y < y0):
            t = (y - y0) / (y1 - y0)
            xs.append(x0 + t * (x1 - x0))
    if len(xs) < 2:
        return None
    return min(xs), max(xs)
