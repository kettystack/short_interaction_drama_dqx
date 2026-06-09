#!/usr/bin/env python3
"""Smoke test for advanced feature endpoints.

Run after backend is up:
    python scripts/advanced_smoke_test.py --base-url http://127.0.0.1:8000
"""
from __future__ import annotations

import argparse
import json
import urllib.request


def request(base_url: str, method: str, path: str, payload: dict | None = None, headers: dict | None = None):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        base_url.rstrip("/") + path,
        data=data,
        method=method,
        headers={"Content-Type": "application/json", **(headers or {})},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        body = resp.read()
    return json.loads(body.decode("utf-8")) if body else {}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    parser.add_argument("--admin-token", default="local-admin-token")
    args = parser.parse_args()

    effects = request(args.base_url, "GET", "/api/assets/effects")
    assert len(effects["effects"]) >= 3, "effect manifest should contain defaults"

    jobs = request(
        args.base_url,
        "GET",
        "/api/aigc-video/jobs?episode_id=ep_063&limit=10",
        headers={"X-Admin-Token": args.admin_token},
    )
    assert jobs, "AIGC jobs should be listable without starting a paid task"
    assert any(job["provider"] == "seedance" for job in jobs), "real Seedance job should exist"

    boost_points = request(args.base_url, "GET", "/api/aigc-video/boost-points/ep_063")
    assert boost_points, "boost points should be listable for the player"
    assert all(point["status"] == "published" for point in boost_points)
    assert any(point["provider"] == "seedance" for point in boost_points)

    gold = request(
        args.base_url,
        "POST",
        "/api/evaluation/gold-labels",
        {
            "episode_id": "ep_063",
            "ts_start": 53,
            "ts_end": 61,
            "type": "剧情悬念",
            "interaction": "炸裂",
            "description": "advanced smoke gold label",
        },
        {"X-Admin-Token": args.admin_token},
    )
    assert gold["id"] > 0, "gold label should be created"

    run = request(
        args.base_url,
        "POST",
        "/api/evaluation/runs",
        {"episode_id": "ep_063", "pipeline_version": "advanced_smoke", "iou_threshold": 0.1},
        {"X-Admin-Token": args.admin_token},
    )
    assert run["items"], "eval run should produce match items"

    thread = request(
        args.base_url,
        "POST",
        "/api/story-chat/threads",
        {
            "episode_id": "ep_063",
            "user_id": "advanced_smoke_story",
            "ts_in_video": 12,
            "context_hint": "向云出山",
            "style_code": "cinematic_literary",
        },
    )
    assert len(thread["turns"]) >= 2, "story chat should append user + assistant turns"

    threads = request(args.base_url, "GET", "/api/story-chat/users/advanced_smoke_story/threads")
    assert threads, "story thread should be persisted and listable"

    auth = request(
        args.base_url,
        "POST",
        "/api/auth/anonymous-login",
        {"device_id": "advanced-smoke-device", "display_name": "测试用户"},
    )
    assert auth["access_token"], "anonymous login should return an access token"

    admin_eps = request(
        args.base_url,
        "GET",
        "/api/admin/episodes?limit=1",
        headers={"X-Admin-Token": args.admin_token},
    )
    assert admin_eps, "admin episode list should be accessible"

    print("advanced-smoke-ok")


if __name__ == "__main__":
    main()
