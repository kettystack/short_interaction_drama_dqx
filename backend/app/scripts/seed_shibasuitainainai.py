"""导入《十八岁太奶奶驾到，重整家族荣耀第三部》剧集与前五集弹幕。

用法：
    cd backend && PYTHONPATH=. python -m app.scripts.seed_shibasuitainainai
"""
from __future__ import annotations

import argparse
import asyncio
import csv
import re
import subprocess
from pathlib import Path
from xml.etree import ElementTree as ET
from zipfile import ZipFile, is_zipfile

from sqlalchemy import delete

from ..config import settings
from ..database import SessionLocal, init_db
from ..models import DanmakuItem, Episode

DRAMA_ID = "shibasuitainainai"
DRAMA_TITLE = "十八岁太奶奶驾到，重整家族荣耀第三部"
EP_PREFIX = "sbtnn_"
EP_RE = re.compile(r"第(\d+)集")
XLSX_NS = {
    "a": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
    "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
}


def col_index(cell_ref: str) -> int:
    letters = "".join(ch for ch in cell_ref if ch.isalpha())
    total = 0
    for ch in letters:
        total = total * 26 + ord(ch.upper()) - 64
    return max(total - 1, 0)


def probe_duration(path: Path) -> float:
    try:
        result = subprocess.run(
            [
                "ffprobe",
                "-v",
                "error",
                "-show_entries",
                "format=duration",
                "-of",
                "default=noprint_wrappers=1:nokey=1",
                str(path),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        return max(float(result.stdout.strip()), 0.0)
    except Exception:
        return 0.0


def iter_xlsx_rows(path: Path):
    with ZipFile(path) as archive:
        shared: list[str] = []
        if "xl/sharedStrings.xml" in archive.namelist():
            root = ET.fromstring(archive.read("xl/sharedStrings.xml"))
            for item in root.findall("a:si", XLSX_NS):
                shared.append("".join(text.text or "" for text in item.findall(".//a:t", XLSX_NS)))

        workbook = ET.fromstring(archive.read("xl/workbook.xml"))
        rels = ET.fromstring(archive.read("xl/_rels/workbook.xml.rels"))
        relmap = {rel.attrib["Id"]: rel.attrib["Target"] for rel in rels}
        first_sheet = workbook.find("a:sheets/a:sheet", XLSX_NS)
        if first_sheet is None:
            return
        rel_id = first_sheet.attrib["{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id"]
        worksheet = ET.fromstring(archive.read("xl/" + relmap[rel_id].lstrip("/")))

        for row in worksheet.findall("a:sheetData/a:row", XLSX_NS):
            values: list[str] = []
            for cell in row.findall("a:c", XLSX_NS):
                idx = col_index(cell.attrib.get("r", "A1"))
                if idx >= len(values):
                    values.extend([""] * (idx - len(values) + 1))
                value = cell.find("a:v", XLSX_NS)
                text = "" if value is None else value.text or ""
                if cell.attrib.get("t") == "s" and text:
                    text = shared[int(text)]
                values[idx] = text
            yield values


def iter_csv_rows(path: Path):
    last_error: UnicodeDecodeError | None = None
    for encoding in ("utf-8-sig", "gb18030"):
        try:
            with path.open("r", encoding=encoding, newline="") as handle:
                for row in csv.reader(handle):
                    yield [cell.strip() for cell in row]
            return
        except UnicodeDecodeError as exc:
            last_error = exc
    if last_error is not None:
        raise last_error


def iter_danmaku_rows(path: Path):
    if is_zipfile(path):
        yield from iter_xlsx_rows(path)
        return
    yield from iter_csv_rows(path)


def episode_id(no: int) -> str:
    return f"{EP_PREFIX}{no:03d}"


async def seed(video_root: Path, source_path: Path, import_danmaku: bool) -> None:
    await init_db()
    files = sorted(
        video_root.glob("第*.mp4"),
        key=lambda item: int(EP_RE.search(item.name).group(1)) if EP_RE.search(item.name) else 0,
    )
    async with SessionLocal() as db:
        for path in files:
            match = EP_RE.search(path.name)
            if not match:
                continue
            no = int(match.group(1))
            item = await db.get(Episode, episode_id(no))
            if item is None:
                item = Episode(
                    id=episode_id(no),
                    drama_id=DRAMA_ID,
                    title=f"{DRAMA_TITLE} 第{no}集",
                    episode_no=no,
                    video_url=f"/videos/shibasuitainainai/{path.name}",
                )
                db.add(item)
            item.duration = probe_duration(path)
            item.video_url = f"/videos/shibasuitainainai/{path.name}"
            item.title = f"{DRAMA_TITLE} 第{no}集"
        await db.commit()

        if not import_danmaku:
            return
        if not source_path.is_file():
            raise FileNotFoundError(f"danmaku source not found: {source_path}")

        ids = [episode_id(no) for no in range(1, 6)]
        await db.execute(
            delete(DanmakuItem).where(
                DanmakuItem.episode_id.in_(ids),
                DanmakuItem.source == "xlsx",
            )
        )

        count = 0
        for row_index, row in enumerate(iter_danmaku_rows(source_path)):
            if row_index == 0 or len(row) < 5:
                continue
            drama_name, group_title, offset_ms, like_count, text = row[:5]
            drama_name = drama_name.strip().strip('"')
            group_title = group_title.strip().strip('"')
            text = text.strip()
            if drama_name != DRAMA_TITLE:
                continue
            match = EP_RE.search(group_title)
            if not match:
                continue
            no = int(match.group(1))
            if no < 1 or no > 5:
                continue
            try:
                ts_in_video = max(float(offset_ms) / 1000, 0)
            except ValueError:
                continue
            db.add(
                DanmakuItem(
                    episode_id=episode_id(no),
                    ts_in_video=ts_in_video,
                    text=text[:256],
                    like_count=int(float(str(like_count).strip() or 0)),
                    source="xlsx",
                    user_id="imported",
                    raw={"drama": drama_name, "group_title": group_title},
                )
            )
            count += 1
        await db.commit()
        print(f"imported {len(files)} episodes and {count} danmaku rows")


def main() -> None:
    parser = argparse.ArgumentParser(description="Seed Shibasui Tainainai episodes and danmaku.")
    parser.add_argument("--video-root", default=settings.shibasuitainainai_video_root)
    parser.add_argument("--source", default="../../圈选剧前5集弹幕.csv")
    parser.add_argument("--skip-danmaku", action="store_true")
    args = parser.parse_args()
    asyncio.run(
        seed(
            Path(args.video_root).resolve(),
            Path(args.source).resolve(),
            not args.skip_danmaku,
        )
    )


if __name__ == "__main__":
    main()