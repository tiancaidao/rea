"""Loads and checks store_products/subscriptions.json, shared by the Play and App Store scripts."""
import json
import os
import re
import sys
from decimal import Decimal, InvalidOperation

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_FILE = os.path.join(SCRIPT_DIR, "subscriptions.json")

# ISO 8601 period -> App Store Connect subscriptionPeriod / intro offer duration.
APPLE_PERIODS = {
    "P1W": "ONE_WEEK",
    "P1M": "ONE_MONTH",
    "P2M": "TWO_MONTHS",
    "P3M": "THREE_MONTHS",
    "P6M": "SIX_MONTHS",
    "P1Y": "ONE_YEAR",
}

PRODUCT_ID = re.compile(r"^[a-z0-9][a-z0-9_.]{0,39}$")
BASE_PLAN_ID = re.compile(r"^[a-z0-9][a-z0-9-]{0,62}$")


def fail(message: str) -> None:
    print(f"Error: {message}", file=sys.stderr)
    sys.exit(1)


def price(value, where: str) -> Decimal:
    try:
        amount = Decimal(str(value))
    except InvalidOperation:
        fail(f"{where}: '{value}' is not a price")
    if amount <= 0 or amount != amount.quantize(Decimal("0.01")):
        fail(f"{where}: '{value}' must be a positive amount with at most 2 decimals")
    return amount


def load(path: str = DEFAULT_FILE) -> dict:
    """Reads the definition file and fails on anything either store would reject."""
    try:
        with open(path, encoding="utf-8") as f:
            config = json.load(f)
    except (OSError, ValueError) as e:
        fail(f"Can't read {path}: {e}")

    seen = set()
    for sub in config.get("subscriptions", []):
        pid = sub.get("product_id", "")
        where = f"subscription '{pid}'"
        if not PRODUCT_ID.match(pid):
            fail(f"{where}: product_id must be lowercase letters, digits, '_' or '.'")
        if pid in seen:
            fail(f"{where}: listed twice")
        seen.add(pid)
        if not BASE_PLAN_ID.match(sub.get("play_base_plan_id", "")):
            fail(f"{where}: play_base_plan_id must be lowercase letters, digits or '-'")
        if sub.get("period") not in APPLE_PERIODS:
            fail(f"{where}: period must be one of {', '.join(APPLE_PERIODS)}")
        sub["price_usd"] = price(sub.get("price_usd"), where)
        offer = sub.get("intro_offer")
        if offer:
            offer["price_usd"] = price(offer.get("price_usd"), f"{where} intro_offer")
            offer["periods"] = int(offer.get("periods", 1))
            if not BASE_PLAN_ID.match(offer.get("play_offer_id", "")):
                fail(f"{where}: intro_offer.play_offer_id must be lowercase letters, digits or '-'")
        if not sub.get("localizations"):
            fail(f"{where}: needs at least one localization")
        for locale, text in sub["localizations"].items():
            # The stricter of the two stores' limits.
            if len(text.get("name", "")) > 30:
                fail(f"{where} {locale}: name is over 30 characters")
            if len(text.get("description", "")) > 55:
                fail(f"{where} {locale}: description is over 55 characters")
            if len(text.get("benefits", [])) > 4 or any(len(b) > 40 for b in text.get("benefits", [])):
                fail(f"{where} {locale}: at most 4 benefits of 40 characters each")
    if not seen:
        fail(f"{path} lists no subscriptions")
    return config


def selected(config: dict, only: list) -> list:
    """The subscriptions to work on: all of them, or the product ids in [only]."""
    subs = config["subscriptions"]
    if not only:
        return subs
    unknown = set(only) - {s["product_id"] for s in subs}
    if unknown:
        fail(f"Not in the definition file: {', '.join(sorted(unknown))}")
    return [s for s in subs if s["product_id"] in only]
