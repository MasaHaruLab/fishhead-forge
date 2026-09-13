"""Excused training pauses (sick / time off) — the streak shield.

A break covers a date range. Weeks fully explained by a break pause the
weekly streak instead of breaking it; the calendar renders break days so an
excuse is always conspicuous, never laundered into the streak invisibly.
An open break (no end date) auto-closes when the next workout is finished —
sickness ends when training resumes. Booked breaks (explicit end) never
auto-close: a hotel-gym session doesn't end a vacation.
"""
from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from backend.core.database import get_db
from backend.core.security import get_current_user
from backend.models import Break, User

router = APIRouter(prefix="/breaks", tags=["breaks"])

KINDS = ["sick", "time_off", "other"]


class BreakIn(BaseModel):
    kind: str
    start_date: date
    end_date: date | None = None
    note: str | None = Field(default=None, max_length=255)


class BreakPatch(BaseModel):
    kind: str | None = None
    start_date: date | None = None
    end_date: date | None = None  # explicit null re-opens the break
    note: str | None = Field(default=None, max_length=255)


def _validate(kind: str, start: date, end: date | None) -> None:
    if kind not in KINDS:
        raise HTTPException(status_code=400, detail="Unknown break kind")
    if end is not None and end < start:
        raise HTTPException(status_code=400, detail="Break ends before it starts")


def _serialize(b: Break) -> dict:
    return {
        "id": b.id,
        "kind": b.kind,
        "start_date": b.start_date.isoformat(),
        "end_date": b.end_date.isoformat() if b.end_date else None,
        "note": b.note,
        "auto_closed": b.auto_closed,
    }


def close_open_break(db: Session, user_id: int, workout_day: date) -> Break | None:
    """A finished workout ends any open break: recovery is defined by training
    resuming. The break closes the day before the session (clamped so a
    same-day start still yields a valid single-day break). Booked breaks —
    explicit end dates — are untouched. Caller commits."""
    open_break = db.execute(
        select(Break).where(
            Break.user_id == user_id,
            Break.end_date.is_(None),
            Break.start_date <= workout_day,
        )
    ).scalars().first()
    if open_break is None:
        return None
    open_break.end_date = max(open_break.start_date, workout_day - timedelta(days=1))
    open_break.auto_closed = True
    db.add(open_break)
    return open_break


@router.get("")
def list_breaks(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    rows = db.execute(
        select(Break).where(Break.user_id == user.id).order_by(Break.start_date.desc())
    ).scalars()
    return [_serialize(b) for b in rows]


@router.post("")
def create(body: BreakIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    _validate(body.kind, body.start_date, body.end_date)
    # Only one "until further notice" break can be running at a time
    if body.end_date is None:
        already_open = db.execute(
            select(Break.id).where(Break.user_id == user.id, Break.end_date.is_(None))
        ).first()
        if already_open:
            raise HTTPException(status_code=409, detail="An open break is already running")
    b = Break(
        user_id=user.id,
        kind=body.kind,
        start_date=body.start_date,
        end_date=body.end_date,
        note=(body.note or None),
    )
    db.add(b)
    db.commit()
    return _serialize(b)


@router.patch("/{break_id}")
def update(
    break_id: int,
    body: BreakPatch,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    b = db.get(Break, break_id)
    if b is None or b.user_id != user.id:
        raise HTTPException(status_code=404, detail="Break not found")
    fields = body.model_dump(exclude_unset=True)
    if "kind" in fields and fields["kind"] is not None:
        b.kind = fields["kind"]
    if "start_date" in fields and fields["start_date"] is not None:
        b.start_date = fields["start_date"]
    if "end_date" in fields:
        b.end_date = fields["end_date"]
        if fields["end_date"] is None:
            b.auto_closed = False  # manually re-opened — no longer a system close
    if "note" in fields:
        b.note = fields["note"] or None
    _validate(b.kind, b.start_date, b.end_date)
    if b.end_date is None:
        other_open = db.execute(
            select(Break.id).where(
                Break.user_id == user.id, Break.end_date.is_(None), Break.id != b.id
            )
        ).first()
        if other_open:
            raise HTTPException(status_code=409, detail="An open break is already running")
    db.add(b)
    db.commit()
    return _serialize(b)


@router.delete("/{break_id}")
def delete(break_id: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    b = db.get(Break, break_id)
    if b is None or b.user_id != user.id:
        raise HTTPException(status_code=404, detail="Break not found")
    db.delete(b)
    db.commit()
    return {"ok": True}
