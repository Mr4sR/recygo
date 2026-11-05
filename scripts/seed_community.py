#!/usr/bin/env python3
"""Seed the RecyGo Community feed with demo listings.

Creates three demo sellers, uploads nine bundled photos to media storage and
publishes nine listings across the three Community filters:

    For Sale (jual)        : 3 listings with a price
    Free (gratis)          : 3 listings with price NULL
    Fuse Together (ajak_fuse) : 3 listings with price NULL

Idempotent: sellers are matched by email, items by exact ``name``, and an
existing listing for an item is never duplicated. ``--reset`` deletes only the
seeded items (cascade removes their listings) and leaves everything else alone.

Stdlib only - no third-party packages. Configuration is read from
``backend/.env`` (``SUPABASE_URL`` and ``SUPABASE_ANON_KEY``). Profiles are
written through the backend's ``PATCH /v1/auth/me`` route.

Usage:
    python scripts/seed_community.py
    python scripts/seed_community.py --reset
    python scripts/seed_community.py --backend http://127.0.0.1:8787 --dry-run
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ENV_PATH = ROOT / "backend" / ".env"
PHOTO_DIR = Path(__file__).resolve().parent / "seed_data" / "photos"

DEFAULT_BACKEND = "http://127.0.0.1:8787"
# Demo credential for the seeded sellers only - not a production secret.
SEED_PASSWORD = "RecyGo!Seed2026"
HTTP_TIMEOUT = 30


# --------------------------------------------------------------------------- #
# Seed content
# --------------------------------------------------------------------------- #

SELLERS = [
    {
        "email": "sari.dewi@recygo.demo",
        "display_name": "Sari Dewi",
        "city": "Jakarta Selatan",
        "lat": -6.2615,
        "lng": 106.8106,
        "bio": "Weekend crafter turning salvaged wood and boxes into new favourites.",
    },
    {
        "email": "budi.santoso@recygo.demo",
        "display_name": "Budi Santoso",
        "city": "Bandung",
        "lat": -6.9175,
        "lng": 107.6191,
        "bio": "Clearing out the workshop. Everything must go this month.",
    },
    {
        "email": "maya.putri@recygo.demo",
        "display_name": "Maya Putri",
        "city": "Yogyakarta",
        "lat": -7.7956,
        "lng": 110.3695,
        "bio": "Collecting jars, fabric and tools for community upcycling sessions.",
    },
]

# Every listing owns exactly one item; photo file -> item -> listing.
LISTINGS = [
    {
        "seller": "sari.dewi@recygo.demo",
        "photo": "wooden-pallets.jpg",
        "name": "Wooden Pallets (Set of 4)",
        "category": "kayu",
        "tags": ["pallets", "wood", "upcycle"],
        "description": (
            "Four solid pine pallets, heat treated and stamped. Dry, no rot, "
            "a few loose boards. Great for a coffee table frame or a herb shelf."
        ),
        "condition": "baik",
        "material": "Pine wood",
        "unit": "paket",
        "quantity": 4,
        "listing_type": "jual",
        "price": 150000,
        "note": "Pickup in Jakarta Selatan this weekend. Bring a van - they stack flat.",
    },
    {
        "seller": "sari.dewi@recygo.demo",
        "photo": "moving-boxes.jpg",
        "name": "Cardboard Moving Boxes (6 pcs)",
        "category": "kertas_kardus",
        "tags": ["cardboard", "boxes", "moving"],
        "description": (
            "Six double-wall moving boxes used once. Folded flat, no water damage. "
            "Perfect for storage or a cardboard build project."
        ),
        "condition": "cukup",
        "material": "Corrugated cardboard",
        "unit": "paket",
        "quantity": 6,
        "listing_type": "gratis",
        "price": None,
        "note": "Free, just collect them from the lobby before Friday.",
    },
    {
        "seller": "sari.dewi@recygo.demo",
        "photo": "old-books.jpg",
        "name": "Old Books Bundle (12 pcs)",
        "category": "kertas_kardus",
        "tags": ["books", "paper", "craft"],
        "description": (
            "A dozen out-of-print paperbacks with yellowed pages and worn spines. "
            "Ideas: folded book art, hidden storage box, or a lamp shade."
        ),
        "condition": "rusak_ringan",
        "material": "Paper",
        "unit": "paket",
        "quantity": 12,
        "listing_type": "ajak_fuse",
        "price": None,
        "note": "Want to build something together? I have the books, you bring the ideas.",
    },
    {
        "seller": "budi.santoso@recygo.demo",
        "photo": "tin-cans.jpg",
        "name": "Empty Tin Cans (20 pcs)",
        "category": "logam",
        "tags": ["tin", "cans", "planter"],
        "description": (
            "Twenty clean cans, labels removed, rims smooth. Ideal for balcony "
            "planters, lanterns or a wall organiser."
        ),
        "condition": "baik",
        "material": "Tin plate",
        "unit": "paket",
        "quantity": 20,
        "listing_type": "jual",
        "price": 25000,
        "note": "Bagged and ready. Meet near Bandung station.",
    },
    {
        "seller": "budi.santoso@recygo.demo",
        "photo": "laptop-motherboard.jpg",
        "name": "Laptop Motherboard (Salvage)",
        "category": "elektronik",
        "tags": ["electronics", "board", "repair"],
        "description": (
            "Dead laptop board, kept for parts: heatsinks, connectors and screws "
            "are still good. Nothing powers on. Handle as e-waste."
        ),
        "condition": "rusak_berat",
        "material": "PCB, copper, aluminium",
        "unit": "satuan",
        "quantity": 1,
        "listing_type": "jual",
        "price": 250000,
        "note": "Selling for the recoverable parts. Cash on pickup in Bandung.",
    },
    {
        "seller": "budi.santoso@recygo.demo",
        "photo": "ceramic-pots.jpg",
        "name": "Ceramic Flower Pots (3 pcs)",
        "category": "lainnya",
        "tags": ["ceramic", "pots", "plants"],
        "description": (
            "Three glazed ceramic pots, one with a chipped rim that still drains "
            "fine. Sizes 12 cm to 20 cm. Fuse idea: mosaic tile tray."
        ),
        "condition": "cukup",
        "material": "Glazed ceramic",
        "unit": "paket",
        "quantity": 3,
        "listing_type": "ajak_fuse",
        "price": None,
        "note": "Chipped one is perfect for a mosaic project - let's smash and rebuild.",
    },
    {
        "seller": "maya.putri@recygo.demo",
        "photo": "white-tshirt.jpg",
        "name": "Plain White Cotton T-Shirt",
        "category": "kain_tekstil",
        "tags": ["cotton", "tshirt", "fabric"],
        "description": (
            "Single white cotton tee, size M, washed but never worn. Perfect base "
            "for a screen print or a tote bag pattern."
        ),
        "condition": "baru",
        "material": "Cotton",
        "unit": "satuan",
        "quantity": 1,
        "listing_type": "gratis",
        "price": None,
        "note": "Free to a good home - Yogyakarta pickup or I can post it.",
    },
    {
        "seller": "maya.putri@recygo.demo",
        "photo": "glass-jars.jpg",
        "name": "Glass Jars (5 pcs)",
        "category": "kaca",
        "tags": ["glass", "jars", "storage"],
        "description": (
            "Five clear jars with matching lids, 500 ml each. Cleaned and "
            "label-free. Great for pantry storage, terrariums or candle making."
        ),
        "condition": "baik",
        "material": "Glass",
        "unit": "paket",
        "quantity": 5,
        "listing_type": "gratis",
        "price": None,
        "note": "Giveaway - take all five, I only ask that you reuse them.",
    },
    {
        "seller": "maya.putri@recygo.demo",
        "photo": "plastic-bucket.jpg",
        "name": "Purple Plastic Bucket",
        "category": "plastik",
        "tags": ["plastic", "bucket", "garden"],
        "description": (
            "Sturdy 10 litre bucket, faded on one side but no cracks. Fuse idea: "
            "self-watering planter or a compost caddy for the kitchen."
        ),
        "condition": "baik",
        "material": "HDPE plastic",
        "unit": "satuan",
        "quantity": 1,
        "listing_type": "ajak_fuse",
        "price": None,
        "note": "Anyone want to turn this into a self-watering planter together?",
    },
]

SEEDED_ITEM_NAMES = {spec["name"] for spec in LISTINGS}


# --------------------------------------------------------------------------- #
# HTTP plumbing
# --------------------------------------------------------------------------- #


class HttpResult:
    __slots__ = ("status", "payload", "text")

    def __init__(self, status: int, payload, text: str) -> None:
        self.status = status
        self.payload = payload
        self.text = text

    @property
    def ok(self) -> bool:
        return 200 <= self.status < 300

    def describe(self) -> str:
        if isinstance(self.payload, dict):
            for key in ("error", "message", "msg"):
                value = self.payload.get(key)
                if isinstance(value, str) and value:
                    return value
        return (self.text or "").strip()[:300] or f"HTTP {self.status}"


def http_call(
    method: str,
    url: str,
    body=None,
    headers: dict | None = None,
    raw: bytes | None = None,
) -> HttpResult:
    data = raw
    hdrs = dict(headers or {})
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        hdrs.setdefault("Content-Type", "application/json")
    request = urllib.request.Request(url, data=data, method=method, headers=hdrs)
    try:
        with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT) as response:
            text = response.read().decode("utf-8", "replace")
            status = response.status
    except urllib.error.HTTPError as exc:
        text = exc.read().decode("utf-8", "replace")
        status = exc.code
    except urllib.error.URLError as exc:
        raise SystemExit(f"Network error calling {url}: {exc.reason}") from exc
    payload = None
    if text.strip():
        try:
            payload = json.loads(text)
        except json.JSONDecodeError:
            payload = None
    return HttpResult(status, payload, text)


def read_env(path: Path) -> dict:
    values: dict[str, str] = {}
    if not path.exists():
        raise SystemExit(f"Missing config file: {path}")
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        values[key.strip()] = value
    return values


# --------------------------------------------------------------------------- #
# RecyGo client
# --------------------------------------------------------------------------- #


class SeedError(RuntimeError):
    pass


class RecyGoSeed:
    def __init__(self, backend: str, env: dict, dry_run: bool = False) -> None:
        self.backend = backend.rstrip("/")
        self.supabase_url = env.get("SUPABASE_URL", "").rstrip("/")
        self.anon_key = env.get("SUPABASE_ANON_KEY", "")
        self.dry_run = dry_run
        self._tokens: dict[str, str] = {}
        if not self.supabase_url or not self.anon_key:
            raise SystemExit(
                "backend/.env must define SUPABASE_URL and SUPABASE_ANON_KEY."
            )

    # -- low level ----------------------------------------------------------

    def api(self, method: str, path: str, body=None, token: str | None = None,
            raw: bytes | None = None, content_type: str | None = None) -> HttpResult:
        headers = {}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        if content_type:
            headers["Content-Type"] = content_type
        return http_call(method, f"{self.backend}{path}", body=body, headers=headers, raw=raw)

    def _expect(self, result: HttpResult, what: str) -> HttpResult:
        if not result.ok:
            raise SeedError(f"{what} failed ({result.status}): {result.describe()}")
        return result

    # -- auth ---------------------------------------------------------------

    def supabase_sign_in(self, email: str, password: str) -> str:
        result = http_call(
            "POST",
            f"{self.supabase_url}/auth/v1/token?grant_type=password",
            body={"email": email, "password": password},
            headers={"apikey": self.anon_key},
        )
        if not result.ok:
            detail = result.describe()
            if "confirm" in detail.lower():
                raise SeedError(
                    f"{email} exists but its email is not confirmed. Confirm it in "
                    "Supabase Auth or remove the account and re-run the seeder."
                )
            raise SeedError(f"Sign-in failed for {email}: {detail}")
        payload = result.payload or {}
        token = payload.get("access_token")
        if not token:
            raise SeedError(f"Sign-in for {email} returned no access token.")
        return token

    def auth(self, seller: dict) -> str:
        email = seller["email"]
        if email in self._tokens:
            return self._tokens[email]
        if self.dry_run:
            return ""
        created = self.api(
            "POST",
            "/v1/auth/register",
            {"data": {
                "email": email,
                "password": SEED_PASSWORD,
                "displayName": seller["display_name"],
            }},
        )
        if created.status not in (200, 201, 409):
            raise SeedError(
                f"Registering {email} failed ({created.status}): {created.describe()}"
            )
        token = self.supabase_sign_in(email, SEED_PASSWORD)
        self._tokens[email] = token
        print(f"  {'reused' if created.status == 409 else 'created'} account {email}")
        return token

    # -- profiles -----------------------------------------------------------

    def ensure_profile(self, seller: dict, token: str) -> None:
        if self.dry_run:
            print(f"  would set profile for {seller['email']}")
            return
        profile = {
            "display_name": seller["display_name"],
            "city": seller["city"],
            "lat": seller["lat"],
            "lng": seller["lng"],
            "bio": seller["bio"],
        }
        self._expect(
            self.api("PATCH", "/v1/auth/me", {"data": profile}, token=token),
            f"Profile update for {seller['email']}",
        )

    # -- items / media ------------------------------------------------------

    def list_items(self, token: str) -> list[dict]:
        result = self._expect(self.api("GET", "/v1/items", token=token), "Loading items")
        payload = result.payload or []
        return payload if isinstance(payload, list) else []

    def upload_photo(self, token: str, photo: Path) -> str:
        result = self._expect(
            self.api(
                "POST",
                f"/v1/media/upload?folder=seed&filename={urllib.parse.quote(photo.name)}",
                token=token,
                raw=photo.read_bytes(),
                content_type="image/jpeg",
            ),
            f"Uploading {photo.name}",
        )
        payload = result.payload or {}
        url = payload.get("publicUrl")
        if not isinstance(url, str) or not url:
            raise SeedError(f"Upload of {photo.name} returned no publicUrl.")
        return url

    def create_item(self, token: str, spec: dict, photo_url: str) -> dict:
        payload = {
            "name": spec["name"],
            "category": spec["category"],
            "tags": spec["tags"],
            "description": spec["description"],
            "condition": spec["condition"],
            "material": spec["material"],
            "unit": spec["unit"],
            "quantity": spec["quantity"],
            "photo_urls": [photo_url],
            "original_photo_url": photo_url,
            "status": "tersedia",
        }
        result = self._expect(
            self.api("POST", "/v1/items", {"data": payload}, token=token),
            f"Creating item {spec['name']}",
        )
        item = result.payload or {}
        if not item.get("id"):
            raise SeedError(f"Creating item {spec['name']} returned no id.")
        return item

    def delete_item(self, token: str, item_id: str) -> None:
        self._expect(
            self.api("DELETE", f"/v1/items/{item_id}", token=token),
            f"Deleting item {item_id}",
        )

    # -- listings -----------------------------------------------------------

    def listing_for_item(self, token: str, item_id: str) -> dict | None:
        result = self.api("GET", f"/v1/listings/by-item/{item_id}", token=token)
        if result.status == 404:
            return None
        self._expect(result, f"Checking listing for item {item_id}")
        payload = result.payload or {}
        return payload if isinstance(payload, dict) and payload.get("id") else None

    def create_listing(self, token: str, item_id: str, spec: dict, seller: dict) -> dict:
        body = {
            "item_id": item_id,
            "listing_type": spec["listing_type"],
            "note": spec["note"],
            "lat": seller["lat"],
            "lng": seller["lng"],
        }
        if spec["listing_type"] == "jual":
            body["price"] = spec["price"]
        result = self._expect(
            self.api("POST", "/v1/listings", {"data": body}, token=token),
            f"Publishing {spec['listing_type']} listing for {spec['name']}",
        )
        listing = result.payload or {}
        if not listing.get("id"):
            raise SeedError(f"Publishing listing for {spec['name']} returned no id.")
        return listing

    def listing_counts(self, token: str) -> dict:
        result = self._expect(self.api("GET", "/v1/listings", token=token), "Loading feed")
        rows = result.payload or []
        counts = {"jual": 0, "gratis": 0, "ajak_fuse": 0}
        for row in rows if isinstance(rows, list) else []:
            kind = row.get("listing_type")
            if kind in counts:
                counts[kind] += 1
        return counts


# --------------------------------------------------------------------------- #
# Commands
# --------------------------------------------------------------------------- #


def sellers_by_email() -> dict:
    return {seller["email"]: seller for seller in SELLERS}


def run_reset(client: RecyGoSeed) -> None:
    print("Resetting seeded Community data...")
    removed = 0
    for seller in SELLERS:
        token = client.auth(seller)
        for item in client.list_items(token):
            if item.get("name") in SEEDED_ITEM_NAMES:
                client.delete_item(token, item["id"])
                removed += 1
                print(f"  deleted {item['name']}")
    print(f"Deleted {removed} seeded item(s) and their listings.")


def run_seed(client: RecyGoSeed, dry_run: bool) -> None:
    print(f"Seeding Community listings into {client.backend} ...")
    counts = {"created": 0, "skipped": 0}
    tokens: dict[str, str] = {}
    existing: dict[str, dict] = {}

    for seller in SELLERS:
        print(f"\n{seller['display_name']} <{seller['email']}>")
        token = client.auth(seller)
        tokens[seller["email"]] = token
        client.ensure_profile(seller, token)
        if not dry_run:
            for item in client.list_items(token):
                name = item.get("name")
                if name:
                    existing[f"{seller['email']}\x00{name}"] = item

    for spec in LISTINGS:
        seller = sellers_by_email()[spec["seller"]]
        token = tokens[seller["email"]]
        if dry_run:
            print(f"  would publish {spec['listing_type']:<10} {spec['name']}")
            counts["created"] += 1
            continue

        item = existing.get(f"{seller['email']}\x00{spec['name']}")
        if item is not None:
            listing = client.listing_for_item(token, item["id"])
            if listing is not None:
                print(f"  skip     {spec['listing_type']:<10} {spec['name']} (already live)")
                counts["skipped"] += 1
                continue
            client.create_listing(token, item["id"], spec, seller)
            print(f"  publish  {spec['listing_type']:<10} {spec['name']} (existing item)")
            counts["created"] += 1
            continue

        photo = PHOTO_DIR / spec["photo"]
        if not photo.exists():
            raise SeedError(f"Missing seed photo: {photo}")
        photo_url = client.upload_photo(token, photo)
        item = client.create_item(token, spec, photo_url)
        client.create_listing(token, item["id"], spec, seller)
        print(f"  publish  {spec['listing_type']:<10} {spec['name']}")
        counts["created"] += 1

    if dry_run:
        print(f"\nDry run: {counts['created']} listing(s) planned, nothing written.")
        return

    print("\nCommunity feed now contains:")
    any_token = next(iter(tokens.values()))
    feed = client.listing_counts(any_token)
    print(f"  For Sale      {feed['jual']}")
    print(f"  Free          {feed['gratis']}")
    print(f"  Fuse Together {feed['ajak_fuse']}")
    print(f"\nThis run: {counts['created']} published, {counts['skipped']} already present.")
    print(f"Demo sellers sign in with password: {SEED_PASSWORD}")



def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Seed RecyGo Community listings.")
    parser.add_argument(
        "--backend",
        default=os.environ.get("RECYGO_BACKEND", DEFAULT_BACKEND),
        help=f"Backend base URL (default: {DEFAULT_BACKEND})",
    )
    parser.add_argument(
        "--reset",
        action="store_true",
        help="Delete seeded items (and their listings) before exiting.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the plan without writing anything.",
    )
    args = parser.parse_args(argv)

    env = read_env(ENV_PATH)
    client = RecyGoSeed(args.backend, env, dry_run=args.dry_run)

    try:
        if args.reset:
            if args.dry_run:
                print("Dry run: --reset would delete seeded items only.")
            else:
                run_reset(client)
        if not args.reset:
            run_seed(client, args.dry_run)
    except SeedError as exc:
        print(f"\nERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
