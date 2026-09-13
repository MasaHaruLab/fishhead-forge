import { CalendarDays, ChevronDown, ChevronLeft, ChevronRight, Pencil, Trash2 } from 'lucide-react'
import { useCallback, useEffect, useState } from 'react'
import { api } from '../lib/api'
import { toast } from '../lib/toast'
import { cn } from '../lib/utils'
import Sheet from './Sheet'

export const BREAK_COLORS: Record<string, string> = {
  sick: '#d4a72c', // amber — outside the orange heat ramp, not "failure red"
  time_off: '#3fa7a3', // teal — clearly not the accent, clearly not success
  other: '#8f86c9',
}

export const BREAK_LABELS: Record<string, string> = {
  sick: 'Sick',
  time_off: 'Time off',
  other: 'Other',
}

interface BreakRow {
  id: number
  kind: string
  start_date: string
  end_date: string | null
  note: string | null
  auto_closed: boolean
  days?: number
  rebound_pct?: number | null
}

interface BreaksSummary {
  breaks: BreakRow[]
  days_last_year: Record<string, number>
  count_last_year: number
}

const inputCls =
  'h-12 rounded-lg border border-input bg-card px-4 text-base outline-none focus:ring-2 focus:ring-ring'

const WEEKDAYS = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su']

function iso(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(
    d.getDate(),
  ).padStart(2, '0')}`
}

/** Themed date field: the native <input type="date"> popup can't be styled,
 *  so this renders an in-sheet month grid in the app's own palette instead.
 *  Monday-start, accent-colored selection, optional minimum date. */
function DateField({
  value,
  onChange,
  min,
  placeholder,
}: {
  value: string
  onChange: (v: string) => void
  min?: string
  placeholder?: string
}) {
  const [open, setOpen] = useState(false)
  const [month, setMonth] = useState(() =>
    value ? new Date(`${value}T00:00:00`) : new Date(),
  )

  const first = new Date(month.getFullYear(), month.getMonth(), 1)
  const daysInMonth = new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate()
  const leadingBlanks = (first.getDay() + 6) % 7 // Monday-start
  const todayIso = iso(new Date())

  return (
    <div>
      <button
        type="button"
        onClick={() => {
          setOpen(!open)
          if (value) setMonth(new Date(`${value}T00:00:00`))
        }}
        className={cn(inputCls, 'flex w-full items-center justify-between text-left')}
      >
        <span className={value ? 'tnum' : 'text-muted-foreground'}>
          {value
            ? new Date(`${value}T00:00:00`).toLocaleDateString(undefined, {
                weekday: 'short',
                day: 'numeric',
                month: 'short',
                year: 'numeric',
              })
            : (placeholder ?? 'Pick a date')}
        </span>
        <CalendarDays size={17} className="text-muted-foreground" />
      </button>
      {open && (
        <div className="mt-2 rounded-xl border bg-card p-3">
          <div className="mb-2 flex items-center justify-between">
            <button
              type="button"
              onClick={() => setMonth(new Date(month.getFullYear(), month.getMonth() - 1, 1))}
              className="touch-feedback rounded-full p-1.5 text-muted-foreground"
              aria-label="Previous month"
            >
              <ChevronLeft size={17} />
            </button>
            <span className="text-sm font-semibold">
              {month.toLocaleDateString(undefined, { month: 'long', year: 'numeric' })}
            </span>
            <button
              type="button"
              onClick={() => setMonth(new Date(month.getFullYear(), month.getMonth() + 1, 1))}
              className="touch-feedback rounded-full p-1.5 text-muted-foreground"
              aria-label="Next month"
            >
              <ChevronRight size={17} />
            </button>
          </div>
          <div className="grid grid-cols-7 gap-1">
            {WEEKDAYS.map((d) => (
              <div
                key={d}
                className="pb-0.5 text-center text-[11px] font-semibold text-muted-foreground"
              >
                {d}
              </div>
            ))}
            {Array.from({ length: leadingBlanks }, (_, i) => (
              <div key={`b-${i}`} />
            ))}
            {Array.from({ length: daysInMonth }, (_, i) => {
              const dayIso = iso(new Date(month.getFullYear(), month.getMonth(), i + 1))
              const disabled = min !== undefined && dayIso < min
              const selected = dayIso === value
              return (
                <button
                  key={dayIso}
                  type="button"
                  disabled={disabled}
                  onClick={() => {
                    onChange(dayIso)
                    setOpen(false)
                  }}
                  className={cn(
                    'tnum touch-feedback flex h-9 items-center justify-center rounded-lg text-sm',
                    selected
                      ? 'bg-primary font-semibold text-primary-foreground'
                      : disabled
                        ? 'text-muted-foreground/40'
                        : 'text-foreground',
                    !selected && dayIso === todayIso && 'border border-[color:var(--chart-accent)]',
                  )}
                >
                  {i + 1}
                </button>
              )
            })}
          </div>
        </div>
      )}
    </div>
  )
}

function fmtRange(b: BreakRow): string {
  const start = new Date(`${b.start_date}T00:00:00`).toLocaleDateString(undefined, {
    day: 'numeric',
    month: 'short',
  })
  if (!b.end_date) return `${start} — ongoing`
  const end = new Date(`${b.end_date}T00:00:00`).toLocaleDateString(undefined, {
    day: 'numeric',
    month: 'short',
  })
  return `${start} – ${end}`
}

/** Manage excused training pauses: list with days lost + strength rebound,
 *  and an add/edit form. An empty end date means "until further notice" —
 *  the break closes itself when the next workout is finished. */
export default function BreaksSheet({
  open,
  onClose,
  onChanged,
}: {
  open: boolean
  onClose: () => void
  onChanged: () => void
}) {
  const [summary, setSummary] = useState<BreaksSummary | null>(null)
  const [editing, setEditing] = useState<BreakRow | 'new' | null>(null)
  const [kind, setKind] = useState('sick')
  const [start, setStart] = useState('')
  const [end, setEnd] = useState('')
  const [note, setNote] = useState('')

  const reload = useCallback(() => {
    api<BreaksSummary>('/stats/breaks').then(setSummary).catch(() => {})
  }, [])
  useEffect(() => {
    if (open) reload()
  }, [open, reload])

  const startEdit = (b: BreakRow | 'new') => {
    setEditing(b)
    if (b === 'new') {
      setKind('sick')
      setStart(new Date().toISOString().slice(0, 10))
      setEnd('')
      setNote('')
    } else {
      setKind(b.kind)
      setStart(b.start_date)
      setEnd(b.end_date ?? '')
      setNote(b.note ?? '')
    }
  }

  const save = async () => {
    const body = {
      kind,
      start_date: start,
      end_date: end || null,
      note: note.trim() || null,
    }
    try {
      if (editing === 'new') await api('/breaks', { method: 'POST', body })
      else if (editing) await api(`/breaks/${editing.id}`, { method: 'PATCH', body })
      setEditing(null)
      reload()
      onChanged()
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Could not save break')
    }
  }

  const remove = async (id: number) => {
    try {
      await api(`/breaks/${id}`, { method: 'DELETE' })
      reload()
      onChanged()
    } catch {
      toast('Could not delete break')
    }
  }

  const days = summary?.days_last_year ?? {}

  return (
    <Sheet open={open} onClose={onClose} title="Breaks">
      <div className="flex flex-col gap-3 pt-1">
        <p className="text-xs text-muted-foreground">
          Sick days and time off pause your streak instead of breaking it. A break without an
          end date closes itself when you next train.
        </p>

        {summary && summary.count_last_year > 0 && (
          <div className="flex flex-wrap gap-2 text-xs">
            {Object.entries(days).map(([k, n]) => (
              <span
                key={k}
                className="rounded-full border px-2.5 py-1"
                style={{ borderColor: BREAK_COLORS[k] ?? 'var(--border)' }}
              >
                {BREAK_LABELS[k] ?? k}: {n} day{n === 1 ? '' : 's'} in the past 12 months
              </span>
            ))}
          </div>
        )}

        {editing === null ? (
          <>
            {(summary?.breaks ?? []).length > 0 && (
              <ul className="divide-y divide-border overflow-hidden rounded-xl border bg-card">
                {(summary?.breaks ?? []).map((b) => (
                  <li key={b.id} className="flex items-center gap-3 px-4 py-2.5">
                    <span
                      className="h-2.5 w-2.5 shrink-0 rounded-full"
                      style={{
                        backgroundColor: BREAK_COLORS[b.kind],
                        boxShadow: `0 0 5px ${BREAK_COLORS[b.kind]}88`,
                      }}
                    />
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-sm font-semibold">
                        {BREAK_LABELS[b.kind] ?? b.kind}
                        {b.note && (
                          <span className="ml-1.5 font-normal text-muted-foreground">
                            {b.note}
                          </span>
                        )}
                      </span>
                      <span className="block text-xs text-muted-foreground">
                        {fmtRange(b)}
                        {b.days != null && ` · ${b.days} day${b.days === 1 ? '' : 's'}`}
                        {b.rebound_pct != null && ` · came back at ${b.rebound_pct}%`}
                        {b.auto_closed && ' · ended by training'}
                      </span>
                    </span>
                    <button
                      onClick={() => startEdit(b)}
                      className="touch-feedback rounded-full p-1.5 text-muted-foreground"
                      aria-label="Edit break"
                    >
                      <Pencil size={15} />
                    </button>
                    <button
                      onClick={() => remove(b.id)}
                      className="touch-feedback rounded-full p-1.5 text-muted-foreground"
                      aria-label="Delete break"
                    >
                      <Trash2 size={15} />
                    </button>
                  </li>
                ))}
              </ul>
            )}
            <button
              onClick={() => startEdit('new')}
              className="touch-feedback h-12 rounded-xl bg-primary font-semibold text-primary-foreground"
            >
              Add break
            </button>
          </>
        ) : (
          <div className="flex flex-col gap-3">
            <label className="flex flex-col gap-1.5 text-sm font-medium">
              Reason
              <span className="relative">
                <select
                  value={kind}
                  onChange={(e) => setKind(e.target.value)}
                  className={cn(inputCls, 'w-full appearance-none pr-10')}
                >
                  <option value="sick">Sick</option>
                  <option value="time_off">Time off</option>
                  <option value="other">Other</option>
                </select>
                <ChevronDown
                  size={17}
                  className="pointer-events-none absolute top-1/2 right-3.5 -translate-y-1/2 text-muted-foreground"
                />
              </span>
            </label>
            <div className="flex flex-col gap-1.5 text-sm font-medium">
              From
              <DateField value={start} onChange={setStart} />
            </div>
            <div className="flex flex-col gap-1.5 text-sm font-medium">
              <span className="flex items-baseline justify-between">
                Until
                {end && (
                  <button
                    type="button"
                    onClick={() => setEnd('')}
                    className="text-xs font-normal text-muted-foreground underline"
                  >
                    no end date
                  </button>
                )}
              </span>
              <DateField
                value={end}
                onChange={setEnd}
                min={start || undefined}
                placeholder='Open — "until further notice"'
              />
              <span className="text-xs font-normal text-muted-foreground">
                Leave open and it ends itself when you next train.
              </span>
            </div>
            <label className="flex flex-col gap-1.5 text-sm font-medium">
              Note
              <input
                value={note}
                onChange={(e) => setNote(e.target.value)}
                placeholder="optional"
                maxLength={255}
                className={inputCls}
              />
            </label>
            <div className="flex gap-2">
              <button
                onClick={() => setEditing(null)}
                className="touch-feedback h-12 flex-1 rounded-xl border font-semibold"
              >
                Cancel
              </button>
              <button
                onClick={save}
                disabled={!start}
                className="touch-feedback h-12 flex-1 rounded-xl bg-primary font-semibold text-primary-foreground disabled:opacity-50"
              >
                Save
              </button>
            </div>
          </div>
        )}
      </div>
    </Sheet>
  )
}
