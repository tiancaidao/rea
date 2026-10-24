#!/usr/bin/env python3
"""Set up Lullwake's RevenueCat products, entitlement and offering from subscriptions.json.

Uses the RevenueCat REST API v2. For the App Store and Play apps in the project
it makes sure every subscription is a RevenueCat product,
attaches the subscriptions to the entitlement, and puts one package per
subscription in the offering (made current). The products themselves must
exist in the stores first (play_subscriptions.py, asc_subscriptions.py).
Nothing changes without --apply; without it the script prints what it would do.

Needs REVENUECAT_API_KEY (a v2 secret key, sk_...) and REVENUECAT_PROJECT_ID.

Examples:
  scripts/store_subscriptions.sh revenuecat list
  scripts/store_subscriptions.sh revenuecat sync            # dry run
  scripts/store_subscriptions.sh revenuecat sync --apply
"""
import argparse
import os
import sys
import time

import requests

import products

API = "https://api.revenuecat.com"
STORES = {"app_store": "App Store", "play_store": "Google Play"}


class RevenueCat:
    def __init__(self, apply: bool):
        key = os.environ.get("REVENUECAT_API_KEY", "")
        project = os.environ.get("REVENUECAT_PROJECT_ID", "")
        if not key.startswith("sk_") or not project:
            products.fail("Set REVENUECAT_API_KEY (a v2 secret key, sk_...) and REVENUECAT_PROJECT_ID "
                          "in store_products/.env (see .env.example)")
        self.base = f"/v2/projects/{project}"
        self.apply = apply
        self.session = requests.Session()
        self.session.headers["Authorization"] = f"Bearer {key}"

    def request(self, method: str, path: str, **kwargs) -> dict:
        url = API + (path if path.startswith("/v2/") else self.base + path)
        for attempt in range(4):
            r = self.session.request(method, url, timeout=60, **kwargs)
            if r.status_code != 429 and r.status_code < 500:
                break
            time.sleep(int(r.headers.get("Retry-After", 2 ** attempt)))
        if r.status_code >= 400:
            try:
                details = r.json().get("message", r.text)
            except ValueError:
                details = r.text
            raise RuntimeError(f"{method} {path} -> {r.status_code}: {details}")
        return r.json() if r.content else {}

    def get_all(self, path: str, params: dict = None) -> list:
        items = []
        page = self.request("GET", path, params={"limit": 100, **(params or {})})
        while True:
            items += page.get("items", [])
            if not page.get("next_page"):
                return items
            page = self.request("GET", page["next_page"])

    def post(self, label: str, path: str, body: dict) -> dict:
        """POSTs with --apply; otherwise only prints [label]."""
        print(("  " if self.apply else "  would ") + label)
        if not self.apply:
            return {"id": f"<new {path.rsplit('/', 1)[-1]}>"}
        return self.request("POST", path, json=body)


def store_identifier(store: str, sub: dict) -> str:
    # RevenueCat names a Play subscription by product id and base plan.
    return f"{sub['product_id']}:{sub['play_base_plan_id']}" if store == "play_store" else sub["product_id"]


def store_apps(rc: RevenueCat) -> list:
    apps = [a for a in rc.get_all("/apps") if a.get("type") in STORES]
    if not apps:
        products.fail("The RevenueCat project has no App Store or Play Store app")
    return apps


def cmd_list(rc: RevenueCat, args) -> None:
    for app in store_apps(rc):
        print(f"{STORES[app['type']]} app '{app.get('name')}':")
        for p in sorted(rc.get_all("/products", {"app_id": app["id"]}), key=lambda p: p["store_identifier"]):
            print(f"  {p['store_identifier']}: {p.get('type')}")
    for e in rc.get_all("/entitlements"):
        attached = [p["store_identifier"] for p in rc.get_all(f"/entitlements/{e['id']}/products")]
        print(f"Entitlement '{e['lookup_key']}': {', '.join(sorted(attached)) or 'no products'}")
    for o in rc.get_all("/offerings"):
        print(f"Offering '{o['lookup_key']}'" + (" (current)" if o.get("is_current") else "") + ":")
        for pkg in rc.get_all(f"/offerings/{o['id']}/packages"):
            attached = [p["product"]["store_identifier"] for p in rc.get_all(f"/packages/{pkg['id']}/products")]
            print(f"  {pkg['lookup_key']}: {', '.join(attached) or 'no products'}")


def cmd_sync(rc: RevenueCat, args) -> None:
    config = products.load(args.file)
    settings = config.get("revenuecat", {})
    packs = config.get("credit_packs", [])
    unknown = set(args.only) - {p["product_id"] for p in config["subscriptions"] + packs}
    if unknown:
        products.fail(f"Not in the definition file: {', '.join(sorted(unknown))}")
    subs = [s for s in config["subscriptions"] if not args.only or s["product_id"] in args.only]
    packs = [p for p in packs if not args.only or p["product_id"] in args.only]

    # 1. Products, per store app. sub_products[product_id] = RevenueCat product ids.
    sub_products = {s["product_id"]: [] for s in subs}
    for app in store_apps(rc):
        print(f"{STORES[app['type']]} app '{app.get('name')}':")
        existing = {p["store_identifier"]: p for p in rc.get_all("/products", {"app_id": app["id"]})}
        wanted = [(store_identifier(app["type"], s), "subscription", s["reference_name"], s["product_id"])
                  for s in subs]
        wanted += [(p["product_id"], "consumable", p["display_name"], None) for p in packs]
        for ident, type_, name, sub_id in wanted:
            product = existing.get(ident)
            if product is None and sub_id and app["type"] == "play_store" and sub_id in existing:
                # An older product named by the subscription id alone still works for purchases.
                product = existing[sub_id]
                print(f"  {ident}: using existing product '{sub_id}'")
            if product is None:
                product = rc.post(f"add {type_} {ident}", "/products",
                                  {"store_identifier": ident, "app_id": app["id"], "type": type_,
                                   "display_name": name})
            else:
                print(f"  {product['store_identifier']} exists")
            if sub_id:
                sub_products[sub_id].append(product["id"])

    # 2. Entitlement with every subscription attached.
    ent_def = settings.get("entitlement")
    if ent_def:
        print(f"Entitlement '{ent_def['lookup_key']}':")
        ent = next((e for e in rc.get_all("/entitlements") if e["lookup_key"] == ent_def["lookup_key"]), None)
        attached = set()
        if ent is None:
            ent = rc.post("create", "/entitlements", ent_def)
        else:
            attached = {p["id"] for p in rc.get_all(f"/entitlements/{ent['id']}/products")}
        missing = [pid for ids in sub_products.values() for pid in ids if pid not in attached]
        if missing:
            rc.post(f"attach {len(missing)} subscription product(s)",
                    f"/entitlements/{ent['id']}/actions/attach_products", {"product_ids": missing})
        else:
            print("  subscriptions already attached")

    # 3. Offering: one package per subscription, holding its product in each store.
    off_def = settings.get("offering")
    if off_def:
        print(f"Offering '{off_def['lookup_key']}':")
        offering = next((o for o in rc.get_all("/offerings") if o["lookup_key"] == off_def["lookup_key"]), None)
        packages = {}
        if offering is None:
            offering = rc.post("create", "/offerings",
                               {"lookup_key": off_def["lookup_key"], "display_name": off_def["display_name"]})
        else:
            packages = {p["lookup_key"]: p for p in rc.get_all(f"/offerings/{offering['id']}/packages")}
        for position, sub in enumerate(subs, start=1):
            key = sub.get("revenuecat_package")
            if not key:
                continue
            pkg = packages.get(key)
            attached = set()
            if pkg is None:
                pkg = rc.post(f"add package {key}", f"/offerings/{offering['id']}/packages",
                              {"lookup_key": key, "display_name": sub["reference_name"], "position": position})
            else:
                attached = {p["product"]["id"] for p in rc.get_all(f"/packages/{pkg['id']}/products")}
            missing = [pid for pid in sub_products[sub["product_id"]] if pid not in attached]
            if missing:
                rc.post(f"put {sub['product_id']} in package {key}",
                        f"/packages/{pkg['id']}/actions/attach_products",
                        {"products": [{"product_id": pid, "eligibility_criteria": "all"} for pid in missing]})
            else:
                print(f"  package {key} already holds {sub['product_id']}")
        if off_def.get("make_current") and not offering.get("is_current"):
            rc.post("make it the current offering", f"/offerings/{offering['id']}", {"is_current": True})

    if not rc.apply:
        print("\nDry run: nothing was changed. Run again with --apply to make these changes.")


def main() -> None:
    parser = argparse.ArgumentParser(description="Set up RevenueCat products, entitlement and offering")
    parser.add_argument("command", choices=["list", "sync"])
    parser.add_argument("--file", default=products.DEFAULT_FILE, help="Subscription definition JSON")
    parser.add_argument("--only", action="append", default=[], metavar="PRODUCT_ID",
                        help="Only this product id (repeatable)")
    parser.add_argument("--apply", action="store_true", help="Make the changes (default is a dry run)")
    args = parser.parse_args()

    rc = RevenueCat(args.apply)
    try:
        {"list": cmd_list, "sync": cmd_sync}[args.command](rc, args)
    except RuntimeError as e:
        products.fail(str(e))


if __name__ == "__main__":
    sys.exit(main())
