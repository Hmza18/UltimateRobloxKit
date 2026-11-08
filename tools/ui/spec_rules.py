"""Screen-spec validation rules: the Python twin of library/src/UI/Spec/SpecSchema.luau.

Ported rule for rule from the Luau schema (paths, messages and limits match), so specs can be checked
without Roblox: `python3 urk.py ui validate`, the preview renderer, the dashboard and CI all use it.
Shared fixtures in tests/fixtures/ui-specs/ keep both validators honest (tests/test_ui_specs.py here,
library/tests/ui_specparity.spec.luau in Lune). If you change a rule, change both files.
"""
import json, re, sys, glob, os, math
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
styles = json.load(open(f"{ROOT}/design/tokens/styles.json"))["styles"]
icons = {i["name"] for i in json.load(open(f"{ROOT}/assets/icons/urk/icons.json"))["icons"]}
cart = styles["cartoon"]
STYLE_NAMES = set(styles)
def style_get(name):
    s = dict(cart)
    if name != "cartoon":
        for k, v in styles[name].items():
            if isinstance(v, dict) and k in s: s[k] = {**s[k], **v}
            else: s[k] = v
    return s
FORMATS = {"number","abbrev","percent","time","duration","upper","lower"}
T = {
 "banner": (["title","palette","price"], ["subtitle","icon","image","badge","timer"], None, True),
 "product": (["title","palette","price"], ["subtitle","icon","image","badge","gift","rarity","owned","layout"], None, True),
 "grid": (["items"], ["columns","cellAspect","gap"], None, False),
 "row": (["items"], ["gap","align"], None, False),
 "heading": (["text"], ["size"], None, False),
 "divider": ([], [], None, False),
 "text": (["text"], ["size","color"], None, False),
 "button": ([], ["text","icon","kind","palette","action","price"], [["text","icon"]], True),
 "iconButton": (["icon"], ["label","palette","action","badge","shape"], None, True),
 "currency": (["icon"], ["bind","value","format","palette","plus","action"], [["bind","value"]], True),
 "level": ([], ["bind","level","value","max"], None, False),
 "progress": ([], ["bind","value","max","palette"], None, False),
 "timer": (["seconds"], ["format","icon"], None, False),
 "toggle": (["id","label"], ["value","min","max","step","options","bind"], None, True),
 "slider": (["id","label"], ["value","min","max","step","options","bind"], None, True),
 "dropdown": (["id","label"], ["value","min","max","step","options","bind"], None, True),
 "dayCard": (["day","reward"], ["state","premium","icon","palette"], None, True),
 "listRow": (["title"], ["subtitle","icon","value","progress","button","rank","palette"], None, True),
}
ML = dict(title=60, subtitle=90, heading=60, text=200, message=90, description=200, buttonText=24, label=40, iconLabel=16, badgeText=12, reward=24, amount=24, option=24, note=200)
RAILS = {"left","right","top","bottom","topLeft","topRight","bottomLeft","bottomRight"}
def isnum(v): return isinstance(v,(int,float)) and not isinstance(v,bool) and math.isfinite(v)
def isint(v): return isnum(v) and float(v).is_integer()
def isicon(n): return isinstance(n,str) and (n in icons or (n.endswith("-color") and n[:-6] in icons))
def isaction(v):
    if not isinstance(v,str) or len(v)>200: return False
    c=0
    for p in v.split(";"):
        t=p.strip()
        if t:
            if not re.match(r"^[A-Za-z0-9_]+$",t) and not re.match(r"^[A-Za-z0-9_]+\s*:",t): return False
            c+=1
    return c>0
def ispath(v): return isinstance(v,str) and v!="" and all(re.match(r"^[A-Za-z0-9_]+$",s) for s in v.split("."))
def isid(v): return isinstance(v,str) and len(v)<=48 and re.match(r"^[A-Za-z_][A-Za-z0-9_\-]*$",v)
class C: pass
def _validate(spec):
    """Returns [{'path', 'message'}]; empty means valid."""
    c=C(); c.issues=[]; c.ids={}; c.count=0; c.style=None
    add=lambda p,m: c.issues.append((p,m))
    J=lambda p,k: k if p=="" else p+"."+k
    def text(p,v,lim,label):
        if not isinstance(v,str): return add(p,label+" must be a string")
        if v.strip()=="": return add(p,label+" must not be empty")
        if len(v)>ML[lim]: add(p,f"{label} is {len(v)} characters; the limit is {ML[lim]}")
    def boolean(p,v,l):
        if not isinstance(v,bool): add(p,l+" must be true or false")
    def enum(p,v,allowed,l):
        if not isinstance(v,str) or v not in allowed: add(p,f"unknown {l} {v}")
    def num(p,v,l,mn=None,mx=None):
        if not isnum(v): return add(p,l+" must be a number")
        if mn is not None and v<mn: add(p,f"{l} must be at least {mn}")
        elif mx is not None and v>mx: add(p,f"{l} must be at most {mx}")
    def integer(p,v,l,mn=None,mx=None):
        if not isint(v): return add(p,l+" must be a whole number")
        num(p,v,l,mn,mx)
    def palette(p,v):
        if not isinstance(v,str): add(p,"palette must be a palette name")
        elif c.style and v not in c.style["palette"]: add(p,"unknown palette "+v)
    def skey(p,v,g,l):
        if not isinstance(v,str): return add(p,l+" must be a string")
        if c.style and v not in c.style[g]: add(p,f"unknown {l} {v}")
    def icon(p,v):
        if not isinstance(v,str) or v=="": add(p,"icon must be an icon name")
        elif not isicon(v): add(p,"unknown icon "+v)
    def unknown(p,v,allowed,owner):
        for k in sorted(v):
            if k not in allowed: add(J(p,k),f"unknown field {k} for {owner}")
    def price(p,pr):
        if not isinstance(pr,dict): return add(p,"price must be an object")
        unknown(p,pr,{"kind","amount","currency","productId","gamePassId"},"price")
        k=pr.get("kind")
        if k is None: return add(J(p,"kind"),"kind is required for price")
        if k not in ("robux","currency","free"): return add(J(p,"kind"),f"unknown price kind {k}")
        def eid(f):
            v=pr.get(f)
            if v is not None and (not isint(v) or v<0): add(J(p,f),f+" must be a whole number >= 0 (0 is a placeholder)")
        if k=="robux":
            if "amount" not in pr: add(J(p,"amount"),"robux prices need an amount")
            else: integer(J(p,"amount"),pr["amount"],"amount",1)
            if "productId" not in pr and "gamePassId" not in pr: add(p,"robux prices need productId or gamePassId")
            elif "productId" in pr and "gamePassId" in pr: add(p,"robux prices use productId or gamePassId, not both")
            eid("productId"); eid("gamePassId")
            if "currency" in pr: add(J(p,"currency"),"currency is only used by currency prices")
        elif k=="currency":
            if "amount" not in pr: add(J(p,"amount"),"currency prices need an amount")
            else: integer(J(p,"amount"),pr["amount"],"amount",0)
            if "currency" not in pr: add(J(p,"currency"),"currency prices need a currency icon name")
            else: icon(J(p,"currency"),pr["currency"])
            if "productId" in pr or "gamePassId" in pr: add(p,"productId and gamePassId are only used by robux prices")
        else:
            if pr.get("amount") not in (None,0): add(J(p,"amount"),"free prices have no amount")
            if any(f in pr for f in ("currency","productId","gamePassId")): add(p,"free prices take no currency or ids")
    def badge(p,b):
        if not isinstance(b,dict): return add(p,"badge must be an object")
        unknown(p,b,{"kind","text"},"badge")
        if "kind" not in b: add(J(p,"kind"),"kind is required for badge")
        else: skey(J(p,"kind"),b["kind"],"badges","badge kind")
        if "text" in b: text(J(p,"text"),b["text"],"badgeText","badge text")
    def columns(p,v):
        def one(pp,x,l):
            if not isint(x) or x<1 or x>6: add(pp,f"{l} must be a whole number from 1 to 6")
        if isnum(v): return one(p,v,"columns")
        if not isinstance(v,dict) or not v: return add(p,"columns must be a number or { phone, tablet, desktop, console }")
        unknown(p,v,{"phone","tablet","desktop","console"},"columns")
        for k in ["phone","tablet","desktop","console"]:
            if k in v: one(J(p,k),v[k],"columns."+k)
    def lst(p,l,depth,label,allow_empty):
        if not isinstance(l,list): return add(p,label+" must be a list of elements")
        if not l and not allow_empty: return add(p,label+" must not be empty")
        for i,e in enumerate(l,1): element(f"{p}[{i}]",e,depth)
    def field(kind,k,p,v,depth):
        if k in ("type","id"): return
        if k=="visible": boolean(p,v,k)
        elif k=="note": text(p,v,"note",k)
        elif k=="title": text(p,v,"title","title")
        elif k=="subtitle": text(p,v,"subtitle","subtitle")
        elif k=="text": text(p,v,{"heading":"heading","text":"text","button":"buttonText"}.get(kind,"text"),"text")
        elif k=="label": text(p,v,"iconLabel" if kind=="iconButton" else "label","label")
        elif k=="reward": text(p,v,"reward","reward")
        elif k=="palette": palette(p,v)
        elif k=="price": price(p,v)
        elif k=="icon": icon(p,v)
        elif k=="image":
            if not isinstance(v,str) or not re.match(r"^rbx[A-Za-z]*://.+$",v): add(p,"image must be an asset id such as rbxassetid://123")
        elif k=="badge": badge(p,v)
        elif k in ("timer","seconds"): num(p,v,k,0)
        elif k in ("gift","owned","premium","plus"): boolean(p,v,k)
        elif k=="rarity": skey(p,v,"rarity","rarity")
        elif k=="layout": enum(p,v,{"tall","wide"},"layout")
        elif k=="align": enum(p,v,{"left","center","right"},"align")
        elif k=="shape": enum(p,v,{"square","circle"},"shape")
        elif k=="state": enum(p,v,{"claimed","today","locked"},"dayCard state")
        elif k=="items": lst(p,v,depth+1,"items",False)
        elif k=="columns": columns(p,v)
        elif k=="cellAspect": num(p,v,k,0.25,4)
        elif k=="gap": skey(p,v,"spacing","gap")
        elif k=="size": enum(p,v,{"display","title","heading","label","caption","price"},"text size")
        elif k=="color":
            if not isinstance(v,str) or not re.match(r"^#[0-9A-Fa-f]{6}$",v): add(p,"color must be #RRGGBB")
        elif k=="kind": skey(p,v,"buttons","button kind")
        elif k=="action":
            if not isaction(v): add(p,f"invalid action {v}")
        elif k=="bind":
            if not ispath(v): add(p,f"invalid bind path {v}")
        elif k=="format":
            if kind=="timer": enum(p,v,{"clock","short"},"timer format")
            elif not isinstance(v,str) or v.split(":")[0] not in FORMATS: add(p,f"unknown format {v}")
        elif k=="level": integer(p,v,k,0)
        elif k=="max":
            if kind=="slider": num(p,v,k)
            else:
                num(p,v,k,0)
                if v==0: add(p,"max must be greater than 0")
        elif k=="min": num(p,v,k)
        elif k=="step":
            num(p,v,k)
            if isnum(v) and v<=0: add(p,"step must be greater than 0")
        elif k=="value":
            if kind=="toggle": boolean(p,v,k)
            elif kind=="dropdown": text(p,v,"option","value")
            elif kind=="listRow":
                if isinstance(v,str): text(p,v,"label","value")
                elif not isnum(v): add(p,"value must be a string or a number")
            elif kind=="slider": num(p,v,k)
            else: num(p,v,k,0)
        elif k=="options":
            if not isinstance(v,list) or not v: add(p,"options must be a non-empty list of strings")
            elif len(v)>20: add(p,"options has more than 20 entries")
            else:
                for i,o in enumerate(v,1): text(f"{p}[{i}]",o,"option","option")
        elif k=="day": integer(p,v,k,1,31)
        elif k=="rank": integer(p,v,k,1)
        elif k=="progress":
            if not isinstance(v,dict): add(p,"progress must be an object { value, max, bind, palette }")
            else:
                unknown(p,v,{"value","max","bind","palette"},"progress")
                if "value" in v: num(J(p,"value"),v["value"],"value",0)
                if "max" in v: num(J(p,"max"),v["max"],"max",0)
                if "bind" in v and not ispath(v["bind"]): add(J(p,"bind"),f"invalid bind path {v['bind']}")
                if "palette" in v: palette(J(p,"palette"),v["palette"])
        elif k=="button":
            if not isinstance(v,dict): add(p,"button must be a button element")
            elif v.get("type",None) not in (None,"button"): add(J(p,"type"),"a listRow button must have type button")
            else:
                cp=dict(v); cp["type"]="button"; element(p,cp,depth+1); c.count-=1
    def cross(kind,p,e):
        if kind=="slider":
            lo=e.get("min",0) if isnum(e.get("min")) else 0
            hi=e.get("max",1) if isnum(e.get("max")) else 1
            if lo>=hi: add(J(p,"max"),"max must be greater than min")
            elif isnum(e.get("value")) and not (lo<=e["value"]<=hi): add(J(p,"value"),"value must be between min and max")
        elif kind=="dropdown":
            o=e.get("options")
            if o is None: add(J(p,"options"),"options is required for dropdown")
            elif isinstance(e.get("value"),str) and isinstance(o,list) and e["value"] not in o: add(J(p,"value"),"value must be one of the options")
        elif kind in ("level","progress"):
            if isnum(e.get("value")) and isnum(e.get("max")) and e["value"]>e["max"]: add(J(p,"value"),"value must not exceed max")
        un={"toggle":["min","max","step","options"],"slider":["options"],"dropdown":["min","max","step"]}
        for f in un.get(kind,[]):
            if f in e: add(J(p,f),f"{f} is not used by {kind}")
    def element(p,e,depth):
        c.count+=1
        if not isinstance(e,dict): return add(p,"element must be an object")
        if depth>5: return add(p,"elements are nested too deeply (limit 5)")
        k=e.get("type")
        if k is None: return add(J(p,"type"),"type is required")
        if k not in T: return add(J(p,"type"),f"unknown element type {k}")
        req,opt,anyof,_=T[k]
        allowed={"type","id","visible","note",*req,*opt}
        unknown(p,e,allowed,k)
        for f in req:
            if f not in e: add(J(p,f),f"{f} is required for {k}")
        for g in anyof or []:
            if not any(f in e for f in g): add(p,f"{k} needs "+" or ".join(g))
        if "id" in e:
            i=e["id"]
            if not isid(i): add(J(p,"id"),"id must be an identifier (letters, digits, _ or -)")
            elif i in c.ids: add(J(p,"id"),f"duplicate id {i} (first used at {c.ids[i]})")
            else: c.ids[i]=p
        for key in sorted(e):
            if key in allowed: field(k,key,J(p,key),e[key],depth)
        cross(k,p,e)
    if not isinstance(spec,dict): add("","spec must be an object"); return c.issues
    unknown("",spec,{"spec","id","kind","style","description","window","body","rails","popup"},"spec")
    if spec.get("spec")!=1: add("spec","spec must be 1")
    if "id" not in spec: add("id","id is required")
    elif not isid(spec["id"]): add("id","id must be an identifier (letters, digits, _ or -)")
    if "description" in spec: text("description",spec["description"],"description","description")
    sn=spec.get("style","cartoon")
    if sn not in STYLE_NAMES: add("style",f"unknown style {sn}")
    else: c.style=style_get(sn)
    kind=spec.get("kind")
    if kind is None: add("kind","kind is required")
    elif kind not in ("window","hud","popup"): add("kind",f"unknown kind {kind}"); kind=None
    if kind=="window":
        w=spec.get("window")
        if w is None: add("window","window is required for window screens")
        else:
            unknown("window",w,{"title","headerPalette","sizeClass","closable","scroll","width","height"},"window")
            if "title" not in w: add("window.title","title is required for window")
            else: text("window.title",w["title"],"title","title")
            if "headerPalette" in w: palette("window.headerPalette",w["headerPalette"])
            if "sizeClass" in w: enum("window.sizeClass",w["sizeClass"],{"sm","md","lg","full"},"sizeClass")
        if "body" not in spec: add("body","body is required for window screens")
        else: lst("body",spec["body"],1,"body",False)
    elif kind=="hud":
        r=spec.get("rails")
        if not r: add("rails","rails is required for hud screens")
        else:
            for n in sorted(r):
                if n not in RAILS: add("rails."+n,"unknown rail "+n)
                else: lst("rails."+n,r[n],1,"rail "+n,False)
    elif kind=="popup":
        pp=spec.get("popup")
        if pp is None: add("popup","popup is required for popup screens")
        else:
            unknown("popup",pp,{"variant","title","message","icon","amount","palette","rays","confirmText","cancelText","price"},"popup")
            if "variant" not in pp: add("popup.variant","variant is required for popup")
            else: enum("popup.variant",pp["variant"],{"reward","confirm"},"popup variant")
            if "title" not in pp: add("popup.title","title is required for popup")
            else: text("popup.title",pp["title"],"title","title")
            if "message" in pp: text("popup.message",pp["message"],"message","message")
            if "icon" in pp: icon("popup.icon",pp["icon"])
            if "amount" in pp: text("popup.amount",pp["amount"],"amount","amount")
            if "palette" in pp: palette("popup.palette",pp["palette"])
            for f in ("confirmText","cancelText"):
                if f in pp: text("popup."+f,pp[f],"buttonText",f)
            if "price" in pp: price("popup.price",pp["price"])
        if "body" in spec: lst("body",spec["body"],1,"body",True)
    if kind:
        owned={"window":["window","body"],"hud":["rails"],"popup":["popup","body"]}[kind]
        for f in ("window","body","rails","popup"):
            if f in spec and f not in owned: add(f,f"{f} is not used by {kind} screens")
    if c.count>200: add("",f"screen has {c.count} elements; the limit is 200")
    return c.issues



STYLES = styles


def validate(spec) -> list:
    """Returns [{"path", "message"}] in the Luau schema's order; empty means valid."""
    out = []
    for issue in _validate(spec):
        if isinstance(issue, dict):
            out.append({"path": issue.get("path", ""), "message": issue.get("message", "")})
        else:
            path, message = issue[0], issue[1]
            out.append({"path": path, "message": message})
    return out


def resolve_palettes(style_name: str) -> dict:
    style = STYLES[style_name]
    base = resolve_palettes(style["extends"]) if style.get("extends") else {}
    return {**base, **style.get("palette", {})}


def resolved_style(style_name: str) -> dict:
    style = dict(STYLES[style_name])
    if style.get("extends"):
        parent = resolved_style(style["extends"])

        def merge(a, b):
            out = dict(a)
            for k, v in b.items():
                out[k] = merge(out[k], v) if isinstance(v, dict) and isinstance(out.get(k), dict) else v
            return out
        style = merge(parent, {k: v for k, v in style.items() if k != "extends"})
    return style
