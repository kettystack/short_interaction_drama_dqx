#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio

import httpx


async def run(base_url: str, episode_id: str, user_id: str, generate: bool) -> None:
    headers = {"X-User-Id": user_id}
    async with httpx.AsyncClient(
        base_url=base_url,
        headers=headers,
        timeout=180,
        trust_env=False,
    ) as client:
        response = await client.get(f"/api/branch-video/episodes/{episode_id}/sessions")
        response.raise_for_status()
        sessions = response.json()
        assert sessions, "no branch-video sessions"
        session = sessions[0]
        assert session["options"], "session has no options"
        assert session["resume_at"] >= session["trigger_ts"]
        print(
            f"session={session['session_id']} trigger={session['trigger_ts']} "
            f"resume={session['resume_at']} options={len(session['options'])}"
        )
        if not generate:
            return
        option = session["options"][0]
        selected = await client.post(
            f"/api/branch-video/sessions/{session['session_id']}/select",
            json={
                "option_id": option["id"],
                "client_event_id": f"smoke:{user_id}:{option['id']}",
            },
        )
        selected.raise_for_status()
        payload = selected.json()
        print(
            f"option={option['label']} status={payload['status']} "
            f"ticket={bool(payload.get('playback_ticket'))}"
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    parser.add_argument("--episode-id", default="ep_063")
    parser.add_argument("--user-id", default="branch-video-smoke")
    parser.add_argument("--generate", action="store_true")
    args = parser.parse_args()
    asyncio.run(run(args.base_url, args.episode_id, args.user_id, args.generate))


if __name__ == "__main__":
    main()
