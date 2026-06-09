from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path
from typing import Any

from ...config import settings
from .schemas import InteractiveDramaState, InteractiveGraph, InteractiveRunOut


class InteractiveDramaRepository:
    def __init__(self, data_root: str | Path | None = None) -> None:
        self.root = Path(data_root or settings.data_root) / "interactive_drama"
        self.run_root = self.root / "runs"

    def load_graph(self, drama_id: str) -> InteractiveGraph:
        path = self._graph_path(drama_id)
        if not path.exists():
            raise FileNotFoundError(f"interactive drama graph not found: {path}")
        payload = json.loads(path.read_text(encoding="utf-8"))
        return InteractiveGraph.model_validate(payload)

    def get_run(self, run_id: str) -> InteractiveRunOut | None:
        path = self._run_path(run_id)
        if not path.exists():
            return None
        try:
            return InteractiveRunOut.model_validate(
                json.loads(path.read_text(encoding="utf-8"))
            )
        except (OSError, json.JSONDecodeError, ValueError):
            return None

    def find_active_run(self, drama_id: str, user_id: str) -> InteractiveRunOut | None:
        if not self.run_root.exists():
            return None
        candidates: list[InteractiveRunOut] = []
        for path in self.run_root.glob("*.json"):
            try:
                run = InteractiveRunOut.model_validate(
                    json.loads(path.read_text(encoding="utf-8"))
                )
            except (OSError, json.JSONDecodeError, ValueError):
                continue
            if run.drama_id == drama_id and run.user_id == user_id and run.status == "active":
                candidates.append(run)
        if not candidates:
            return None
        return sorted(candidates, key=lambda item: item.updated_at)[-1]

    def save_run(self, run: InteractiveRunOut) -> InteractiveRunOut:
        self.run_root.mkdir(parents=True, exist_ok=True)
        run.updated_at = datetime.utcnow()
        payload: dict[str, Any] = run.model_dump(mode="json")
        self._run_path(run.run_id).write_text(
            json.dumps(payload, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        return run

    def new_run(
        self,
        *,
        run_id: str,
        graph: InteractiveGraph,
        user_id: str,
        episode_id: str,
        active_node_id: str | None,
    ) -> InteractiveRunOut:
        node = self.node_by_id(graph, active_node_id) if active_node_id else None
        now = datetime.utcnow()
        return InteractiveRunOut(
            run_id=run_id,
            drama_id=graph.drama_id,
            title=graph.title,
            version=graph.version,
            user_id=user_id,
            current_episode_id=episode_id,
            current_node_id=node.node_id if node else None,
            state=InteractiveDramaState(),
            selected_path=[],
            active_node=node,
            created_at=now,
            updated_at=now,
        )

    def node_by_id(self, graph: InteractiveGraph, node_id: str | None):
        if not node_id:
            return None
        for node in graph.nodes:
            if node.node_id == node_id:
                return node
        return None

    def _run_path(self, run_id: str) -> Path:
        safe = "".join(ch for ch in run_id if ch.isalnum() or ch in ("_", "-"))
        return self.run_root / f"{safe}.json"

    def _graph_path(self, drama_id: str) -> Path:
        name = f"{drama_id}_graph.json"
        configured = self.root / name
        if configured.exists():
            return configured
        project_data = Path(__file__).resolve().parents[4] / "data" / "interactive_drama" / name
        if project_data.exists():
            return project_data
        cwd_data = Path.cwd() / "data" / "interactive_drama" / name
        if cwd_data.exists():
            return cwd_data
        return configured
