#!/usr/bin/env python3
"""Create or update Lullwake's Google Play subscriptions from subscriptions.json.

Uses the Play Developer API (monetization.subscriptions) with the service
account key in PLAY_KEY_FILE. Nothing changes without --apply; without it the
script prints what it would do.

Examples:
  scripts/store_subscriptions.sh play list
  scripts/store_subscriptions.sh play sync                  # dry run
  scripts/store_subscriptions.sh play sync --apply
  scripts/store_subscriptions.sh play sync --apply --update-prices --only lullwake_premium_monthly
"""
import argparse
import json
import os
import sys
from decimal import Decimal

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

import products

SCOPES = ["https://www.googleapis.com/auth/androidpublisher"]
# Play's pricing regions version; see the monetization.subscriptions.create docs.
REGIONS_VERSION = "2022/02"


def money(amount: Decimal, currency: str = "USD") -> dict:
    units, fraction = divmod(amount, 1)
    return {"currencyCode": currency, "units": str(int(units)), "nanos": int(fraction * 1_000_000_000)}


def from_money(m: dict) -> Decimal:
    return Decimal(m.get("units", "0")) + Decimal(m.get("nanos", 0)) / 1_000_000_000


def api_error(e: HttpError) -> str:
    try:
        return json.loads(e.content)["error"]["message"]
    except (ValueError, KeyError, TypeError):
        return str(e)


class Play:
    def __init__(self, key_file: str, package: str, apply: bool):
        if not key_file or not os.path.isfile(key_file):
            products.fail(f"Service account key not found: {key_file or '(none)'} "
                          "(pass --key-file or set PLAY_KEY_FILE)")
        creds = service_account.Credentials.from_service_account_file(key_file, scopes=SCOPES)
        self.api = build("androidpublisher", "v3", credentials=creds, cache_discovery=False).monetization()
        self.package = package
        self.apply = apply
        self._prices = {}

    def run(self, label: str, request):
        """Runs [request] with --apply; otherwise only prints [label]."""
        print(("  " if self.apply else "  would ") + label)
        if not self.apply:
            return None
        try:
            return request.execute()
        except HttpError as e:
            products.fail(f"{label} failed: {api_error(e)}")

    def existing(self) -> dict:
        subs, token = {}, None
        while True:
            page = self.api.subscriptions().list(packageName=self.package, pageToken=token, pageSize=100).execute()
            for sub in page.get("subscriptions", []):
                subs[sub["productId"]] = sub
            token = page.get("nextPageToken")
            if not token:
                return subs

    def converted(self, usd: Decimal) -> dict:
        """Play's local price for [usd] in every region it sells in."""
        if usd not in self._prices:
            self._prices[usd] = self.api.convertRegionPrices(
                packageName=self.package, body={"price": money(usd)}).execute()
        return self._prices[usd]

    def base_plan(self, sub: dict) -> dict:
        prices = self.converted(sub["price_usd"])
        return {
            "basePlanId": sub["play_base_plan_id"],
            "autoRenewingBasePlanType": {
                "billingPeriodDuration": sub["period"],
                # RevenueCat and older clients buy by product id alone.
                "legacyCompatible": True,
            },
            "regionalConfigs": [
                {"regionCode": region, "newSubscriberAvailability": True, "price": p["price"]}
                for region, p in sorted(prices.get("convertedRegionPrices", {}).items())
            ],
            "otherRegionsConfig": {**prices.get("convertedOtherRegionsPrice", {}), "newSubscriberAvailability": True},
        }

    def offer(self, sub: dict, intro: dict) -> dict:
        regions = sorted(self.converted(sub["price_usd"]).get("convertedRegionPrices", {}))
        if intro["type"] == "free_trial":
            phase = {"recurrenceCount": 1, "duration": intro["duration"],
                     "regionalConfigs": [{"regionCode": r, "free": {}} for r in regions]}
        else:
            intro_prices = self.converted(intro["price_usd"]).get("convertedRegionPrices", {})
            regions = [r for r in regions if r in intro_prices]
            phase = {"recurrenceCount": intro["periods"], "duration": sub["period"],
                     "regionalConfigs": [{"regionCode": r, "price": intro_prices[r]["price"]} for r in regions]}
        return {
            "packageName": self.package,
            "productId": sub["product_id"],
            "basePlanId": sub["play_base_plan_id"],
            "offerId": intro["play_offer_id"],
            "phases": [phase],
            "regionalConfigs": [{"regionCode": r, "newSubscriberAvailability": True} for r in regions],
            # Like Apple: only for people who never subscribed to anything in the app.
            "targeting": {"acquisitionRule": {"scope": {"anySubscriptionInApp": {}}}},
        }


def listings(sub: dict, current: list = ()) -> list:
    by_language = {l["languageCode"]: l for l in current}
    for locale, text in sub["localizations"].items():
        listing = {"languageCode": locale, "title": text["name"], "description": text["description"]}
        if text.get("benefits"):
            listing["benefits"] = text["benefits"]
        by_language[locale] = listing
    return list(by_language.values())


def us_price(base_plan: dict):
    for config in base_plan.get("regionalConfigs", []):
        if config["regionCode"] == "US":
            return from_money(config["price"])
    return None


def cmd_list(play: Play, args) -> None:
    subs = play.existing()
    if not subs:
        print(f"No subscriptions on Google Play for {play.package}.")
    for pid, sub in sorted(subs.items()):
        print(pid)
        for plan in sub.get("basePlans", []):
            period = plan.get("autoRenewingBasePlanType", {}).get("billingPeriodDuration", "?")
            print(f"  base plan {plan['basePlanId']}: {period}, US ${us_price(plan)}, {plan.get('state')}")
            offers = play.api.subscriptions().basePlans().offers().list(
                packageName=play.package, productId=pid, basePlanId=plan["basePlanId"]).execute()
            for offer in offers.get("subscriptionOffers", []):
                print(f"    offer {offer['offerId']}: {offer.get('state')}")


def cmd_sync(play: Play, args) -> None:
    config = products.load(args.file)
    current = play.existing()
    subs_api = play.api.subscriptions()
    for sub in products.selected(config, args.only):
        pid, plan_id = sub["product_id"], sub["play_base_plan_id"]
        print(f"{pid}:")
        existing = current.get(pid)

        if existing is None:
            play.run(f"create subscription with base plan {plan_id} at ${sub['price_usd']}",
                     subs_api.create(packageName=play.package, productId=pid,
                                     regionsVersion_version=REGIONS_VERSION,
                                     body={"packageName": play.package, "productId": pid,
                                           "listings": listings(sub), "basePlans": [play.base_plan(sub)]}))
            plan_state = "DRAFT"
        else:
            plans = {p["basePlanId"]: p for p in existing.get("basePlans", [])}
            plan = plans.get(plan_id)
            changes = []
            period = (plan or {}).get("autoRenewingBasePlanType", {}).get("billingPeriodDuration")
            if period and period != sub["period"]:
                # Play can't change an active base plan's period; it takes a new base plan id.
                print(f"  base plan {plan_id} bills every {period}, file says {sub['period']}; "
                      "fix it with a new base plan id")
            if listings(sub, existing.get("listings", [])) != existing.get("listings", []):
                changes.append("listings")
            if plan is None:
                plans[plan_id] = play.base_plan(sub)
                changes.append(f"new base plan {plan_id}")
            elif us_price(plan) != sub["price_usd"]:
                if args.update_prices:
                    plans[plan_id] = {**plan, **{k: v for k, v in play.base_plan(sub).items()
                                                  if k in ("regionalConfigs", "otherRegionsConfig")}}
                    changes.append(f"price ${us_price(plan)} -> ${sub['price_usd']} for new subscribers")
                else:
                    print(f"  price is ${us_price(plan)}, file says ${sub['price_usd']}; "
                          "pass --update-prices to change it")
            if changes:
                body = {**existing, "listings": listings(sub, existing.get("listings", [])),
                        "basePlans": list(plans.values())}
                play.run("update " + ", ".join(changes),
                         subs_api.patch(packageName=play.package, productId=pid,
                                        updateMask="listings,basePlans",
                                        regionsVersion_version=REGIONS_VERSION, body=body))
            else:
                print("  listings and price already match")
            plan_state = plans[plan_id].get("state", "DRAFT")

        if plan_state != "ACTIVE":
            play.run(f"activate base plan {plan_id}",
                     subs_api.basePlans().activate(packageName=play.package, productId=pid,
                                                   basePlanId=plan_id, body={}))

        intros = products.offers_for(sub, "play")
        if not intros:
            continue
        offers = {}
        if existing is not None and plan_id in {p["basePlanId"] for p in existing.get("basePlans", [])}:
            page = subs_api.basePlans().offers().list(
                packageName=play.package, productId=pid, basePlanId=plan_id).execute()
            offers = {o["offerId"]: o for o in page.get("subscriptionOffers", [])}
        for intro in intros:
            offer_id = intro["play_offer_id"]
            offer = offers.get(offer_id)
            if offer is None:
                play.run(f"create offer {offer_id}: {products.describe(intro, sub['period'])}",
                         subs_api.basePlans().offers().create(
                             packageName=play.package, productId=pid, basePlanId=plan_id, offerId=offer_id,
                             regionsVersion_version=REGIONS_VERSION, body=play.offer(sub, intro)))
            else:
                # Changing a live offer's price changes it for everyone mid-offer, so leave that to Play Console.
                print(f"  offer {offer_id} exists ({offer.get('state')}); edit it in Play Console")
            if offer is None or offer.get("state") != "ACTIVE":
                play.run(f"activate offer {offer_id}",
                         subs_api.basePlans().offers().activate(
                             packageName=play.package, productId=pid, basePlanId=plan_id,
                             offerId=offer_id, body={}))

    if not play.apply:
        print("\nDry run: nothing was changed. Run again with --apply to make these changes.")


def main() -> None:
    parser = argparse.ArgumentParser(description="Create or update Google Play subscriptions")
    parser.add_argument("command", choices=["list", "sync"])
    parser.add_argument("--file", default=products.DEFAULT_FILE, help="Subscription definition JSON")
    parser.add_argument("--key-file", default=os.environ.get("PLAY_KEY_FILE"),
                        help="Service account key JSON (default: PLAY_KEY_FILE)")
    parser.add_argument("--package-name", default=os.environ.get("PLAY_PACKAGE_NAME"),
                        help="Application ID (default: android_package in the definition file)")
    parser.add_argument("--only", action="append", default=[], metavar="PRODUCT_ID",
                        help="Only this product id (repeatable)")
    parser.add_argument("--update-prices", action="store_true",
                        help="Change a base plan's price when it differs from the file (new subscribers only)")
    parser.add_argument("--apply", action="store_true", help="Make the changes (default is a dry run)")
    args = parser.parse_args()

    package = args.package_name or products.load(args.file)["android_package"]
    play = Play(args.key_file, package, args.apply)
    try:
        {"list": cmd_list, "sync": cmd_sync}[args.command](play, args)
    except HttpError as e:
        products.fail(api_error(e))


if __name__ == "__main__":
    sys.exit(main())
