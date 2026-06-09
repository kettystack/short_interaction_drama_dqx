from __future__ import annotations

import hashlib
import time
from datetime import datetime

from fastapi import HTTPException

from .repository import InteractiveDramaRepository
from .schemas import (
    InteractiveChooseIn,
    InteractiveChooseOut,
    InteractiveRunCreateIn,
    InteractiveRunOut,
)
from .state_engine import (
    apply_state_delta,
    build_story_text,
    evaluate_condition,
    evaluate_ending,
    pick_next_node,
)


class InteractiveDramaService:
    def __init__(self, repository: InteractiveDramaRepository | None = None) -> None:
        self.repo = repository or InteractiveDramaRepository()

    async def start_run(self, payload: InteractiveRunCreateIn) -> InteractiveRunOut:
        graph = self._load_graph(payload.drama_id)
        if not payload.reset:
            existing = self.repo.find_active_run(payload.drama_id, payload.user_id)
            if existing:
                existing.active_node = self.repo.node_by_id(graph, existing.current_node_id)
                return existing
        run = self.repo.new_run(
            run_id=self._run_id(payload.drama_id, payload.user_id),
            graph=graph,
            user_id=payload.user_id,
            episode_id=payload.episode_id,
            active_node_id=graph.initial_node_id,
        )
        return self.repo.save_run(run)

    async def get_run(self, run_id: str) -> InteractiveRunOut:
        run = self.repo.get_run(run_id)
        if run is None:
            raise HTTPException(404, "interactive run not found")
        graph = self._load_graph(run.drama_id)
        run.active_node = self.repo.node_by_id(graph, run.current_node_id)
        return run

    async def choose(
        self,
        run_id: str,
        payload: InteractiveChooseIn,
    ) -> InteractiveChooseOut:
        run = await self.get_run(run_id)
        if run.status != "active":
            raise HTTPException(400, "interactive run is not active")
        graph = self._load_graph(run.drama_id)
        node = self.repo.node_by_id(graph, payload.node_id)
        if node is None:
            raise HTTPException(404, "interactive node not found")
        if run.current_node_id != node.node_id:
            raise HTTPException(400, "node is not active for current run")
        option = next((item for item in node.options if item.option_id == payload.option_id), None)
        if option is None:
            raise HTTPException(404, "interactive option not found")
        if option.condition and not evaluate_condition(run.state, option.condition):
            raise HTTPException(400, "interactive option condition is not satisfied")

        before = run.state
        after, changes = apply_state_delta(before, option)
        next_node = pick_next_node(graph, option, after)
        ending = evaluate_ending(graph, after) if next_node is None else None
        story_text = build_story_text(
            node=node,
            option=option,
            state_after=after,
            ending=ending,
        )
        path_item = {
            "node_id": node.node_id,
            "question": node.question,
            "option_id": option.option_id,
            "label": option.label,
            "description": option.description,
            "state_before": before.model_dump(mode="json"),
            "state_after": after.model_dump(mode="json"),
            "state_changes": changes,
            "story_text": story_text,
            "created_at": datetime.utcnow().isoformat(),
            "client_event_id": payload.client_event_id,
        }
        run.state = after
        run.selected_path.append(path_item)
        run.current_node_id = next_node.node_id if next_node else None
        run.current_episode_id = next_node.episode_id if next_node else run.current_episode_id
        run.active_node = next_node
        run.ending = ending
        run.status = "ended" if ending else "active"
        self.repo.save_run(run)
        return InteractiveChooseOut(
            run=run,
            story_text=story_text,
            state_changes=changes,
            next_node=next_node,
            ending=ending,
            playback_ticket=None,
        )

    async def reset_run(self, run_id: str) -> InteractiveRunOut:
        run = await self.get_run(run_id)
        graph = self._load_graph(run.drama_id)
        reset = self.repo.new_run(
            run_id=self._run_id(run.drama_id, run.user_id),
            graph=graph,
            user_id=run.user_id,
            episode_id="txy_001",
            active_node_id=graph.initial_node_id,
        )
        return self.repo.save_run(reset)

    async def rewind_run(self, run_id: str) -> InteractiveRunOut:
        run = await self.get_run(run_id)
        if not run.selected_path:
            return await self.reset_run(run_id)
        graph = self._load_graph(run.drama_id)
        last = run.selected_path.pop()
        previous_node_id = str(last.get("node_id") or graph.initial_node_id)
        previous_state = last.get("state_before") or {}
        previous_node = self.repo.node_by_id(graph, previous_node_id)
        if previous_node is None:
            previous_node = self.repo.node_by_id(graph, graph.initial_node_id)
        if previous_node is None:
            raise HTTPException(404, "interactive node not found")
        run.state = type(run.state).model_validate(previous_state)
        run.current_node_id = previous_node.node_id
        run.current_episode_id = previous_node.episode_id
        run.active_node = previous_node
        run.ending = None
        run.status = "active"
        return self.repo.save_run(run)

    def _load_graph(self, drama_id: str):
        try:
            return self.repo.load_graph(drama_id)
        except FileNotFoundError as exc:
            raise HTTPException(404, str(exc)) from exc

    def _run_id(self, drama_id: str, user_id: str) -> str:
        digest = hashlib.sha1(f"{drama_id}:{user_id}:{time.time_ns()}".encode("utf-8")).hexdigest()[:10]
        return f"irun_{drama_id}_{digest}"
