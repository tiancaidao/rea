#!/usr/bin/env python3
"""Set up the app's RevenueCat products, entitlement and offering from subscriptions.json.

Uses the RevenueCat REST API v2. sync adds each subscription and one-time
product to the project's App Store and Play Store apps, attaches them all to
the entitlement, and puts one package per product in the offering, holding
that product in each store. It never deletes anything. Nothing changes
without --apply; without it the script prints what it would do.

Needs REVENUECAT_API_KEY (a v2 secret key with project configuration read and
write) and REVENUECAT_PROJECT_ID, from fastlane/.env.

Examples:
  python3 store_products/revenuecat_products.py list
  python3 store_products/revenuecat_products.py sync                  # dry run
  python3 store_products/revenuecat_products.py sync --apply
"""
import argparse
import os
import sys

import requests

import products

API = "https://api.revenuecat.com"


class RevenueCat:
    def __init__(self, apply: bool):
        key = os.environ.get("REVENUECAT_API_KEY", "")
        self.project = os.environ.get("REVENUECAT_PROJECT_ID", "")
        if not key or not self.project:
            products.fail("Set REVENUECAT_API_KEY and REVENUECAT_PROJECT_ID (see fastlane/.env.example)")
        self.apply = apply
        self.session = requests.Session()
        self.session.headers["Authorization"] = f"Bearer {key}"

    def _url(self, path: str) -> str:
        if path.startswith("/v2/"):
            return API + path
        return f"{API}/v2/projects/{self.project}{path}"

    def _check(self, r: requests.Response, what: str) -> dict:
        if r.status_code >= 400:
            try:
                message = r.json().get("message", r.text)
            except ValueError:
                message = r.text
            products.fail(f"{what} failed ({r.status_code}): {message}")
        return r.json() if r.content else {}

    def get_all(self, path: str) -> list:
        items, url = [], self._url(path)
        while url:
            page = self._check(self.session.get(url, params={"limit": 100}), f"GET {path}")
            items += page.get("items", [])
            url = self._url(page["next_page"]) if page.get("next_page") else None
        return items

    def post(self, label: str, path: str, body: dict) -> dict:
        """Posts [body] with --apply; otherwise only prints [label] and returns {}."""
        print(("  " if self.apply else "  would ") + label)
        if not self.apply:
            return {}
        return self._check(self.session.post(self._url(path), json=body), label)


def store_apps(rc: RevenueCat, config: dict) -> dict:
    """The project's App Store and Play Store apps for this bundle id and package, by store."""
    wanted = {"app_store": config["ios_bundle_id"], "play_store": config["android_package"]}
    apps = {}
    for app in rc.get_all("/apps"):
        store = app.get("type")
        ident = (app.get(store) or {}).get("bundle_id" if store == "app_store" else "package_name")
        if store in wanted and ident == wanted[store]:
            apps[store] = app
    for store, ident in wanted.items():
        if store not in apps:
            print(f"Note: no {store} app for {ident} in the RevenueCat project; skipping that store. "
                  "Add it in RevenueCat (Apps & providers) with its store credentials.")
    return apps


def product_specs(config: dict) -> list:
    """(package lookup key, display name, type, store identifier by store) for every product."""
    specs = []
    for sub in config["subscriptions"]:
        pid = sub["product_id"]
        specs.append((sub.get("revenuecat_package", f"${pid}"), sub["reference_name"], "subscription",
                      {"app_store": pid, "play_store": f"{pid}:{sub['play_base_plan_id']}"}))
    for one in config["revenuecat"].get("one_time_products", []):
        pid = one["product_id"]
        specs.append((one.get("revenuecat_package", f"${pid}"), one["display_name"], "one_time",
                      {"app_store": pid, "play_store": pid}))
    return specs


def cmd_list(rc: RevenueCat, config: dict) -> None:
    apps = store_apps(rc, config)
    app_names = {a["id"]: s for s, a in apps.items()}
    print("Products:")
    for p in rc.get_all("/products"):
        if p.get("app_id") in app_names:
            print(f"  {app_names[p['app_id']]:10} {p['store_identifier']:28} {p.get('type', '')}")
    print("Entitlements:")
    for e in rc.get_all("/entitlements"):
        attached = [p.get("store_identifier", p["id"]) for p in rc.get_all(f"/entitlements/{e['id']}/products")]
        print(f"  {e['lookup_key']}: {', '.join(attached) or '(no products)'}")
    print("Offerings:")
    for o in rc.get_all("/offerings"):
        print(f"  {o['lookup_key']}{' (current)' if o.get('is_current') else ''}")
        for pkg in rc.get_all(f"/offerings/{o['id']}/packages"):
            attached = [p["product"]["store_identifier"] if "product" in p else p.get("store_identifier", "")
                        for p in rc.get_all(f"/packages/{pkg['id']}/products")]
            print(f"    {pkg['lookup_key']}: {', '.join(attached) or '(no products)'}")


def cmd_sync(rc: RevenueCat, config: dict) -> None:
    rc_config = config["revenuecat"]
    apps = store_apps(rc, config)
    if not apps:
        products.fail("Nothing to sync: the project has neither store app.")

    # 1. Products, one per store app.
    print("Products:")
    existing = {(p["app_id"], p["store_identifier"]): p for p in rc.get_all("/products")}
    by_package = {}  # package lookup key -> product ids in RevenueCat
    for package, name, kind, idents in product_specs(config):
        ids = by_package.setdefault(package, [])
        for store, app in apps.items():
            ident = idents[store]
            product = existing.get((app["id"], ident))
            if product:
                print(f"  {store} {ident} exists")
            else:
                product = rc.post(f"create {store} product {ident}", "/products",
                                  {"store_identifier": ident, "app_id": app["id"], "type": kind,
                                   "display_name": name})
            if product.get("id"):
                ids.append(product["id"])
    all_ids = [i for ids in by_package.values() for i in ids]

    # 2. Entitlement holding every product.
    print("Entitlement:")
    want = rc_config["entitlement"]
    entitlement = next((e for e in rc.get_all("/entitlements") if e["lookup_key"] == want["lookup_key"]), None)
    if entitlement is None:
        entitlement = rc.post(f"create entitlement {want['lookup_key']}", "/entitlements", want)
    if entitlement.get("id"):
        attached = {p["id"] for p in rc.get_all(f"/entitlements/{entitlement['id']}/products")}
        missing = [i for i in all_ids if i not in attached]
        if missing:
            rc.post(f"attach {len(missing)} product(s) to {want['lookup_key']}",
                    f"/entitlements/{entitlement['id']}/actions/attach_products", {"product_ids": missing})
        elif all_ids:
            print(f"  {want['lookup_key']} has every product")
    elif not rc.apply:
        print(f"  would attach {len(all_ids) or 'all'} product(s) to {want['lookup_key']}")

    # 3. Offering: one package per product, holding it in each store.
    print("Offering:")
    want = rc_config["offering"]
    offering = next((o for o in rc.get_all("/offerings") if o["lookup_key"] == want["lookup_key"]), None)
    if offering is None:
        offering = rc.post(f"create offering {want['lookup_key']}", "/offerings",
                           {"lookup_key": want["lookup_key"], "display_name": want["display_name"]})
    packages = {}
    if offering.get("id"):
        packages = {p["lookup_key"]: p for p in rc.get_all(f"/offerings/{offering['id']}/packages")}
    for position, (package, name, _, _) in enumerate(product_specs(config), start=1):
        pkg = packages.get(package)
        if pkg is None:
            pkg = rc.post(f"create package {package}", f"/offerings/{offering.get('id', '<new>')}/packages",
                          {"lookup_key": package, "display_name": name, "position": position})
        ids = by_package.get(package, [])
        attached = set()
        if pkg.get("id"):
            for p in rc.get_all(f"/packages/{pkg['id']}/products"):
                attached.add(p["product"]["id"] if "product" in p else p.get("id"))
        missing = [i for i in ids if i not in attached]
        if missing or (not rc.apply and not ids):
            rc.post(f"attach {len(missing) or 'its'} product(s) to package {package}",
                    f"/packages/{pkg.get('id', '<new>')}/actions/attach_products",
                    {"products": [{"product_id": i, "eligibility_criteria": "all"} for i in missing]})
        else:
            print(f"  package {package} has its products")
    if want.get("make_current") and not offering.get("is_current"):
        rc.post(f"make {want['lookup_key']} the current offering", f"/offerings/{offering.get('id', '<new>')}",
                {"is_current": True})

    if not rc.apply:
        print("\nDry run: nothing changed. Add --apply to make these changes.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["list", "sync"])
    parser.add_argument("--apply", action="store_true", help="make the changes (sync is a dry run without it)")
    parser.add_argument("--file", default=products.DEFAULT_FILE, help="definition file")
    args = parser.parse_args()

    config = products.load(args.file)
    if "revenuecat" not in config:
        products.fail(f"{args.file} has no revenuecat section")
    rc = RevenueCat(apply=args.apply)
    if args.command == "list":
        cmd_list(rc, config)
    else:
        cmd_sync(rc, config)


if __name__ == "__main__":
    try:
        main()
    except requests.RequestException as e:
        products.fail(f"Network error: {e}")
    except KeyboardInterrupt:
        sys.exit(130)
