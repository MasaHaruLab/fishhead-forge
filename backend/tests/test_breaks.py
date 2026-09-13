"""Breaks (sick / time off): the streak shield.

Contract: an excused week PAUSES the weekly streak — it bridges a gap without
counting toward the number. A break only rescues weeks that would otherwise
fail; a trained week counts normally even inside a booked vacation. Open
breaks auto-close when the next workout is finished; booked ones never do.
"""
from datetime import date, timedelta

from backend.api.breaks import close_open_break
from backend.api.stats import breaks_summary, stats
from backend.models import Break

from .conftest import TODAY, log_workout, make_exercise

WEEK = timedelta(weeks=1)


def _monday(d: date) -> date:
    return d - timedelta(days=d.weekday())


def _train_weeks_ago(db, user, ex, weeks_ago, weight=100.0, reps=5):
    # Wednesday of that week, so week membership is unambiguous
    monday = _monday(TODAY) - WEEK * weeks_ago
    days_ago = (TODAY - monday).days - 2
    return log_workout(db, user, days_ago, [(ex, [(weight, reps)])])


def test_streak_unbroken_by_excused_weeks(db, user, freeze_now):
    ex = make_exercise(db)
    # Trained weeks: 4, 3 ago and current week; weeks 2 and 1 ago fully sick
    for weeks_ago in (4, 3, 0):
        _train_weeks_ago(db, user, ex, weeks_ago)
    sick_start = _monday(TODAY) - WEEK * 2
    db.add(Break(user_id=user.id, kind="sick",
                 start_date=sick_start, end_date=sick_start + timedelta(days=13)))
    db.commit()

    data = stats(tz_offset=0, user=user, db=db)
    # Pause, not break: 3 trained weeks count, 2 sick weeks bridge
    assert data["streak_weeks"] == 3
    assert data["streak_excused_weeks"] == 2
    assert data["extras"]["longest_streak_weeks"] == 3


def test_unexcused_gap_still_breaks(db, user, freeze_now):
    ex = make_exercise(db)
    for weeks_ago in (4, 3, 0):
        _train_weeks_ago(db, user, ex, weeks_ago)
    data = stats(tz_offset=0, user=user, db=db)
    assert data["streak_weeks"] == 1
    assert data["streak_excused_weeks"] == 0


def test_trained_vacation_week_counts_normally(db, user, freeze_now):
    ex = make_exercise(db)
    for weeks_ago in (2, 1, 0):
        _train_weeks_ago(db, user, ex, weeks_ago)
    # Vacation covering last week — but it was trained anyway
    vac_start = _monday(TODAY) - WEEK
    db.add(Break(user_id=user.id, kind="time_off",
                 start_date=vac_start, end_date=vac_start + timedelta(days=6)))
    db.commit()
    data = stats(tz_offset=0, user=user, db=db)
    assert data["streak_weeks"] == 3
    assert data["streak_excused_weeks"] == 0


def test_open_break_shields_and_marks_calendar(db, user, freeze_now):
    ex = make_exercise(db)
    _train_weeks_ago(db, user, ex, 2)
    _train_weeks_ago(db, user, ex, 1)
    # Sick since Saturday of last week, still open
    db.add(Break(user_id=user.id, kind="sick", start_date=TODAY - timedelta(days=2)))
    db.commit()
    data = stats(tz_offset=0, user=user, db=db)
    assert data["streak_weeks"] == 2  # current excused week starts the walk
    by_date = {d["date"]: d for d in data["calendar"]}
    assert by_date[TODAY.isoformat()]["break_kind"] == "sick"
    assert by_date[(TODAY - timedelta(days=3)).isoformat()]["break_kind"] is None


def test_excused_weeks_before_first_workout_dont_count(db, user, freeze_now):
    ex = make_exercise(db)
    _train_weeks_ago(db, user, ex, 0)
    old = _monday(TODAY) - WEEK * 3
    db.add(Break(user_id=user.id, kind="sick",
                 start_date=old, end_date=old + timedelta(days=20)))
    db.commit()
    data = stats(tz_offset=0, user=user, db=db)
    assert data["streak_weeks"] == 1
    assert data["streak_excused_weeks"] == 0


def test_auto_close_only_touches_open_breaks(db, user, freeze_now):
    booked = Break(user_id=user.id, kind="time_off",
                   start_date=TODAY - timedelta(days=3),
                   end_date=TODAY + timedelta(days=4))
    open_sick = Break(user_id=user.id, kind="sick", start_date=TODAY - timedelta(days=5))
    db.add_all([booked, open_sick])
    db.commit()

    closed = close_open_break(db, user.id, TODAY)
    db.commit()
    assert closed is open_sick
    assert open_sick.end_date == TODAY - timedelta(days=1)
    assert open_sick.auto_closed is True
    assert booked.end_date == TODAY + timedelta(days=4)  # untouched

    # Same-day start clamps to a one-day break instead of ending before it began
    same_day = Break(user_id=user.id, kind="sick", start_date=TODAY)
    db.add(same_day)
    db.commit()
    close_open_break(db, user.id, TODAY)
    db.commit()
    assert same_day.end_date == TODAY


def test_rebound_compares_before_and_after(db, user, freeze_now):
    ex = make_exercise(db)
    # 100 e1RM-ish before the break, weaker after
    log_workout(db, user, 20, [(ex, [(100.0, 1)])])
    log_workout(db, user, 2, [(ex, [(90.0, 1)])])
    db.add(Break(user_id=user.id, kind="sick",
                 start_date=TODAY - timedelta(days=14), end_date=TODAY - timedelta(days=5)))
    db.commit()
    data = breaks_summary(user=user, db=db)
    assert data["count_last_year"] == 1
    assert data["days_last_year"] == {"sick": 10}
    b = data["breaks"][0]
    assert b["days"] == 10
    assert b["rebound_pct"] == 90.0
