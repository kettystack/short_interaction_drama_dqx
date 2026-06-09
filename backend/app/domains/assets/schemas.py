from __future__ import annotations

from pydantic import BaseModel, Field


class EffectAnimationSpec(BaseModel):
    type: str = "custom_painter"
    preset: str = "ignition"
    duration_ms: int = 900


class EffectSoundSpec(BaseModel):
    url: str = ""
    volume: float = 0.8


class InteractionEffectAssetOut(BaseModel):
    code: str
    label: str
    actions: list[str] = Field(default_factory=list)
    icon: str = ""
    animation: EffectAnimationSpec = Field(default_factory=EffectAnimationSpec)
    sound: EffectSoundSpec | None = None
    haptic: str = "light"
    colors: list[str] = Field(default_factory=list)


class InteractionEffectManifestOut(BaseModel):
    version: str
    effects: list[InteractionEffectAssetOut] = Field(default_factory=list)

