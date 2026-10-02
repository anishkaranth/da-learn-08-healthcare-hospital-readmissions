"""Minimal builders for a Lakeview (AI/BI) dashboard serialized JSON (.lvdash.json)."""


def ds(name, display, sql):
    return {"name": name, "displayName": display, "queryLines": [sql]}


def _field(n):
    return {"name": n, "expression": f"`{n}`"}


def _widget(name, ds_name, cols, spec, pos):
    return {"widget": {"name": name, "queries": [{"name": "main_query", "query": {
        "datasetName": ds_name, "fields": [_field(c) for c in cols], "disaggregated": True}}], "spec": spec}, "position": pos}


def text(name, md, x, y, w=6, h=1):
    return {"widget": {"name": name, "multilineTextboxSpec": {"lines": [md]}}, "position": {"x": x, "y": y, "width": w, "height": h}}


PCT = {"type": "number-percent", "decimalPlaces": {"type": "max", "places": 2}}
NUM = {"type": "number", "abbreviation": "compact", "decimalPlaces": {"type": "max", "places": 1}}
USD = {"type": "number-currency", "currencyCode": "USD", "abbreviation": "compact", "decimalPlaces": {"type": "max", "places": 1}}


def counter(name, ds_name, col, title, fmt, x, y, w=1, h=2):
    enc = {"fieldName": col, "displayName": title}
    if fmt:
        enc["format"] = fmt
    return _widget(name, ds_name, [col], {"version": 2, "widgetType": "counter", "encodings": {"value": enc},
                   "frame": {"showTitle": True, "title": title}}, {"x": x, "y": y, "width": w, "height": h})


def chart(name, kind, ds_name, x, y, title, pos, xs="categorical", ys="quantitative", horizontal=False, color=None):
    """kind: bar | line | scatter. x / y / color = (field, display name)."""
    xe = {"fieldName": x[0], "displayName": x[1], "scale": {"type": xs}}
    ye = {"fieldName": y[0], "displayName": y[1], "scale": {"type": ys}}
    enc = {"x": ye, "y": xe} if horizontal else {"x": xe, "y": ye}
    cols = [x[0], y[0]]
    if color:
        enc["color"] = {"fieldName": color[0], "displayName": color[1], "scale": {"type": "categorical"}}
        cols.append(color[0])
    return _widget(name, ds_name, cols, {"version": 3, "widgetType": kind, "encodings": enc,
                   "frame": {"showTitle": True, "title": title}}, pos)


def page(name, display, layout):
    return {"name": name, "displayName": display, "pageType": "PAGE_TYPE_CANVAS", "layout": layout}


def count_visuals(dash):
    return sum(1 for p in dash["pages"] for w in p["layout"] if "spec" in w["widget"])
