#!/usr/bin/env python3
"""Create or update Lullwake's App Store subscriptions from subscriptions.json.

Uses the App Store Connect API with an API key from the environment
(ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH or ASC_KEY_CONTENT_BASE64; the
wrapper script can load them from the file named by ASC_ENV_FILE). Nothing
changes without --apply; without it the script prints what it would do.

Examples:
  scripts/store_subscriptions.sh ios list
  scripts/store_subscriptions.sh ios sync                  # dry run
  scripts/store_subscriptions.sh ios sync --apply
  scripts/store_subscriptions.sh ios sync --apply --update-prices --only lullwake_premium_monthly
"""
import argparse
import base64
import json
import os
import sys
import time
from decimal import Decimal

import jwt
import requests

import products

API = "https://api.appstoreconnect.apple.com"
HOME_TERRITORY = "USA"


class AppStoreConnect:
    def __init__(self, apply: bool):
        key_id = os.environ.get("ASC_KEY_ID", "")
        issuer_id = os.environ.get("ASC_ISSUER_ID", "")
        if not key_id or not issuer_id:
            products.fail("Set ASC_KEY_ID and ASC_ISSUER_ID, or ASC_ENV_FILE in store_products/.env")
        if os.environ.get("ASC_KEY_CONTENT_BASE64"):
            key = base64.b64decode(os.environ["ASC_KEY_CONTENT_BASE64"]).decode()
        else:
            path = os.path.expanduser(os.environ.get("ASC_KEY_PATH", ""))
            if not os.path.isfile(path):
                products.fail(f"Set ASC_KEY_PATH to your AuthKey_{key_id}.p8")
            with open(path, encoding="utf-8") as f:
                key = f.read()
        self.key_id, self.issuer_id, self.key = key_id, issuer_id, key
        self.apply = apply
        self.session = requests.Session()
        self._token_expires = 0

    def _auth(self) -> None:
        now = int(time.time())
        if now < self._token_expires - 60:
            return
        self._token_expires = now + 15 * 60  # Apple allows at most 20 minutes.
        token = jwt.encode({"iss": self.issuer_id, "iat": now, "exp": self._token_expires,
                            "aud": "appstoreconnect-v1"},
                           self.key, algorithm="ES256", headers={"kid": self.key_id, "typ": "JWT"})
        self.session.headers["Authorization"] = f"Bearer {token}"

    def request(self, method: str, path: str, **kwargs) -> dict:
        self._auth()
        url = path if path.startswith("http") else API + path
        for attempt in range(4):
            r = self.session.request(method, url, timeout=60, **kwargs)
            if r.status_code != 429 and r.status_code < 500:
                break
            time.sleep(2 ** attempt)
        if r.status_code >= 400:
            try:
                details = "; ".join(e.get("detail") or e.get("title", "") for e in r.json()["errors"])
            except (ValueError, KeyError):
                details = r.text
            raise RuntimeError(f"{method} {path} -> {r.status_code}: {details}")
        return r.json() if r.content else {}

    def get_all(self, path: str, params: dict = None) -> tuple:
        """Every page of a list: (data, included)."""
        data, included = [], []
        page = self.request("GET", path, params={"limit": 200, **(params or {})})
        while True:
            data += page.get("data", [])
            included += page.get("included", [])
            next_url = page.get("links", {}).get("next")
            if not next_url:
                return data, included
            page = self.request("GET", next_url)

    def create(self, label: str, type_: str, attributes: dict, relationships: dict) -> dict:
        """POSTs a new [type_] resource with --apply; otherwise only prints [label]."""
        if label:
            print(("  " if self.apply else "  would ") + label)
        if not self.apply:
            return {"id": f"<new {type_}>"}
        rels = {name: {"data": value} for name, value in relationships.items()}
        body = {"data": {"type": type_, "attributes": attributes, "relationships": rels}}
        return self.request("POST", f"/v1/{type_}", json=body)["data"]

    def update(self, label: str, type_: str, id_: str, attributes: dict) -> None:
        print(("  " if self.apply else "  would ") + label)
        if self.apply:
            self.request("PATCH", f"/v1/{type_}/{id_}",
                         json={"data": {"type": type_, "id": id_, "attributes": attributes}})


def ref(type_: str, id_: str) -> dict:
    return {"type": type_, "id": id_}


def find_app(asc: AppStoreConnect, bundle_id: str) -> str:
    apps = asc.request("GET", "/v1/apps", params={"filter[bundleId]": bundle_id})["data"]
    if not apps:
        products.fail(f"No app with bundle id {bundle_id} in App Store Connect (or the API key can't see it)")
    return apps[0]["id"]


def groups_and_subscriptions(asc: AppStoreConnect, app_id: str) -> tuple:
    groups, _ = asc.get_all(f"/v1/apps/{app_id}/subscriptionGroups")
    subs = {}
    for group in groups:
        data, _ = asc.get_all(f"/v1/subscriptionGroups/{group['id']}/subscriptions")
        for sub in data:
            subs[sub["attributes"]["productId"]] = {**sub, "group": group}
    return groups, subs


def price_points(asc: AppStoreConnect, sub_id: str, territory: str = HOME_TERRITORY) -> dict:
    """customerPrice -> price point id for one territory."""
    data, _ = asc.get_all(f"/v1/subscriptions/{sub_id}/pricePoints",
                          {"filter[territory]": territory, "fields[subscriptionPricePoints]": "customerPrice"})
    return {Decimal(p["attributes"]["customerPrice"]): p["id"] for p in data}


def equalized(asc: AppStoreConnect, point_id: str) -> list:
    """(territory, price point id) for [point_id] and Apple's equivalent in every other territory."""
    data, _ = asc.get_all(f"/v1/subscriptionPricePoints/{point_id}/equalizations",
                          {"include": "territory", "fields[subscriptionPricePoints]": "customerPrice,territory"})
    pairs = [(point_territory(p), p["id"]) for p in data]
    return [(HOME_TERRITORY, point_id)] + [(t, i) for t, i in pairs if t != HOME_TERRITORY]


def point_territory(point: dict) -> str:
    territory = (point.get("relationships", {}).get("territory") or {}).get("data")
    if territory:
        return territory["id"]
    # Price point ids are base64 JSON that names the territory as "t".
    encoded = point["id"] + "=" * (-len(point["id"]) % 4)
    return json.loads(base64.urlsafe_b64decode(encoded))["t"]


def has_availability(asc: AppStoreConnect, sub_id: str) -> bool:
    try:
        return bool(asc.request("GET", f"/v1/subscriptions/{sub_id}/subscriptionAvailability").get("data"))
    except RuntimeError as e:
        if " 404:" in str(e):
            return False
        raise


def home_prices(asc: AppStoreConnect, sub_id: str) -> list:
    """The subscription's current and scheduled US prices."""
    data, included = asc.get_all(f"/v1/subscriptions/{sub_id}/prices",
                                 {"filter[territory]": HOME_TERRITORY, "include": "subscriptionPricePoint"})
    points = {p["id"]: Decimal(p["attributes"]["customerPrice"]) for p in included
              if p["type"] == "subscriptionPricePoints"}
    return [points.get(p["relationships"]["subscriptionPricePoint"]["data"]["id"]) for p in data]


def point_for(points: dict, amount: Decimal, product_id: str) -> str:
    if amount not in points:
        near = sorted(points, key=lambda p: abs(p - amount))[:3]
        products.fail(f"{product_id}: Apple has no ${amount} price point; nearest are "
                      + ", ".join(f"${p}" for p in near))
    return points[amount]


def sync_localizations(asc, kind: str, parent_rel: str, parent_id: str, current: list, wanted: dict) -> None:
    by_locale = {l["attributes"]["locale"]: l for l in current}
    for locale, text in wanted.items():
        attributes = {k: v for k, v in text.items() if k in ("name", "description", "customAppName")}
        have = by_locale.get(locale)
        if have is None:
            asc.create(f"add {locale} localization", kind, {"locale": locale, **attributes},
                       {parent_rel: ref(parent_rel + "s", parent_id)})
        elif any(have["attributes"].get(k) != v for k, v in attributes.items()):
            asc.update(f"update {locale} localization", kind, have["id"], attributes)


def cmd_list(asc: AppStoreConnect, args) -> None:
    config = products.load(args.file)
    app_id = find_app(asc, args.bundle_id or config["ios_bundle_id"])
    groups, subs = groups_and_subscriptions(asc, app_id)
    if not groups:
        print("No subscription groups yet.")
    for group in groups:
        print(f"Group '{group['attributes']['referenceName']}'")
        for pid, sub in sorted(subs.items()):
            if sub["group"]["id"] != group["id"]:
                continue
            a = sub["attributes"]
            prices = ", ".join(f"${p}" for p in home_prices(asc, sub["id"]) if p is not None) or "no price"
            print(f"  {pid}: {a.get('subscriptionPeriod')}, level {a.get('groupLevel')}, "
                  f"US {prices}, {a.get('state')}")


def cmd_sync(asc: AppStoreConnect, args) -> None:
    config = products.load(args.file)
    app_id = find_app(asc, args.bundle_id or config["ios_bundle_id"])
    groups, subs = groups_and_subscriptions(asc, app_id)

    group_def = config["subscription_group"]
    group = next((g for g in groups if g["attributes"]["referenceName"] == group_def["reference_name"]), None)
    print(f"Group '{group_def['reference_name']}':")
    if group is None:
        group = asc.create("create subscription group", "subscriptionGroups",
                           {"referenceName": group_def["reference_name"]}, {"app": ref("apps", app_id)})
        current_locs = []
    else:
        current_locs, _ = asc.get_all(f"/v1/subscriptionGroups/{group['id']}/subscriptionGroupLocalizations")
    sync_localizations(asc, "subscriptionGroupLocalizations", "subscriptionGroup", group["id"],
                       current_locs, group_def.get("localizations", {}))

    territories = None
    for sub in products.selected(config, args.only):
        pid = sub["product_id"]
        print(f"{pid}:")
        existing = subs.get(pid)
        attributes = {"name": sub["reference_name"], "groupLevel": sub["group_level"],
                      "reviewNote": sub.get("review_note", "")}
        is_new = existing is None
        if is_new:
            created = asc.create(f"create {products.APPLE_PERIODS[sub['period']]} subscription",
                                 "subscriptions",
                                 {"productId": pid, "subscriptionPeriod": products.APPLE_PERIODS[sub["period"]],
                                  "familySharable": False, **attributes},
                                 {"group": ref("subscriptionGroups", group["id"])})
            sub_id = created["id"]
        else:
            sub_id = existing["id"]
            if existing["group"]["id"] != group["id"]:
                print(f"  is in group '{existing['group']['attributes']['referenceName']}'; "
                      "Apple can't move a subscription between groups")
            a = existing["attributes"]
            if a.get("subscriptionPeriod") != products.APPLE_PERIODS[sub["period"]]:
                print(f"  period is {a.get('subscriptionPeriod')} in App Store Connect; change it there if allowed")
            changed = {k: v for k, v in attributes.items() if a.get(k) != v}
            if changed:
                asc.update("update " + ", ".join(changed), "subscriptions", sub_id, changed)

        if not asc.apply and is_new:
            # The rest needs the new subscription's id and its price points.
            intros = products.offers_for(sub, "ios")
            print(f"  would add localizations, availability in all territories, price ${sub['price_usd']}"
                  + (f" and intro offer: {products.describe(intros[0], sub['period'])}" if intros else ""))
            continue

        current_locs = [] if is_new else asc.get_all(f"/v1/subscriptions/{sub_id}/subscriptionLocalizations")[0]
        sync_localizations(asc, "subscriptionLocalizations", "subscription", sub_id,
                           current_locs, sub["localizations"])

        if not has_availability(asc, sub_id):
            if territories is None:
                territories = [t["id"] for t in asc.get_all("/v1/territories")[0]]
            asc.create(f"make available in all {len(territories)} territories", "subscriptionAvailabilities",
                       {"availableInNewTerritories": True},
                       {"subscription": ref("subscriptions", sub_id),
                        "availableTerritories": [ref("territories", t) for t in territories]})

        points = price_points(asc, sub_id)
        prices = home_prices(asc, sub_id)
        target = sub["price_usd"]
        if target in prices:
            print(f"  price ${target} already set")
        elif prices and not args.update_prices:
            print(f"  price is {', '.join(f'${p}' for p in prices)}, file says ${target}; "
                  "pass --update-prices to change it")
        else:
            preserve = bool(prices) and not args.no_preserve_price
            pairs = equalized(asc, point_for(points, target, pid))
            print(("  " if asc.apply else "  would ") + f"set price ${target} in {len(pairs)} territories"
                  + (" (existing subscribers keep their price)" if preserve else ""))
            for territory, point_id in pairs:
                asc.create("", "subscriptionPrices", {"startDate": None, "preserveCurrentPrice": preserve},
                           {"subscription": ref("subscriptions", sub_id),
                            "subscriptionPricePoint": ref("subscriptionPricePoints", point_id),
                            "territory": ref("territories", territory)})

        for intro in products.offers_for(sub, "ios"):
            offers, _ = asc.get_all(f"/v1/subscriptions/{sub_id}/introductoryOffers")
            if offers:
                print(f"  intro offer exists in {len(offers)} territories; edit it in App Store Connect")
                continue
            if intro["type"] == "free_trial":
                # A free trial has no price, so one offer per territory the subscription sells in.
                pairs = equalized(asc, point_for(points, sub["price_usd"], pid))
                attributes = {"duration": products.APPLE_PERIODS[intro["duration"]], "offerMode": "FREE_TRIAL",
                              "numberOfPeriods": 1, "startDate": None, "endDate": None}
            else:
                pairs = equalized(asc, point_for(points, intro["price_usd"], pid))
                attributes = {"duration": products.APPLE_PERIODS[sub["period"]], "offerMode": "PAY_AS_YOU_GO",
                              "numberOfPeriods": intro["periods"], "startDate": None, "endDate": None}
            print(("  " if asc.apply else "  would ") + f"add intro offer ({products.describe(intro, sub['period'])}) "
                  f"in {len(pairs)} territories")
            for territory, point_id in pairs:
                rels = {"subscription": ref("subscriptions", sub_id), "territory": ref("territories", territory)}
                if intro["type"] != "free_trial":
                    rels["subscriptionPricePoint"] = ref("subscriptionPricePoints", point_id)
                asc.create("", "subscriptionIntroductoryOffers", attributes, rels)

    if not asc.apply:
        print("\nDry run: nothing was changed. Run again with --apply to make these changes.")
    else:
        print("\nDone. Each new subscription still needs a review screenshot in App Store Connect "
              "before it can be submitted with an app version.")


def main() -> None:
    parser = argparse.ArgumentParser(description="Create or update App Store subscriptions")
    parser.add_argument("command", choices=["list", "sync"])
    parser.add_argument("--file", default=products.DEFAULT_FILE, help="Subscription definition JSON")
    parser.add_argument("--bundle-id", default=os.environ.get("APP_IDENTIFIER"),
                        help="Bundle id (default: ios_bundle_id in the definition file)")
    parser.add_argument("--only", action="append", default=[], metavar="PRODUCT_ID",
                        help="Only this product id (repeatable)")
    parser.add_argument("--update-prices", action="store_true",
                        help="Change a subscription's price when it differs from the file")
    parser.add_argument("--no-preserve-price", action="store_true",
                        help="With --update-prices, move existing subscribers to the new price too")
    parser.add_argument("--apply", action="store_true", help="Make the changes (default is a dry run)")
    args = parser.parse_args()

    asc = AppStoreConnect(args.apply)
    try:
        {"list": cmd_list, "sync": cmd_sync}[args.command](asc, args)
    except RuntimeError as e:
        products.fail(str(e))


if __name__ == "__main__":
    sys.exit(main())
