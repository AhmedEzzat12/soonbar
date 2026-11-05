# Using Soonbar

## Quick add

Press ⌥⌘N anywhere (or **New** in the popover) and type. The form below fills in as you go; anything you change
by hand stays put.

| You type | You get |
|---|---|
| `Focus block` | Event today at the next half hour, 30 minutes |
| `Review for 45m` · `Planning 1h30m` | Event with that length |
| `Offsite tomorrow` | All-day event |
| `Workshop friday from 2pm to 4pm` | Event 14:00–16:00 on Friday |
| `Coffee tomorrow 11` · `Gym friday 9` | A bare hour is a time (1–6 mean the afternoon) |
| `Design review next Tuesday 3pm` | "next"/"this" stay out of the title |
| `Standup 9:30 #work` | Event in the calendar whose name matches `work` |
| `!Call mom tomorrow at 6pm` | Start with `!` for a reminder |
| `!Renew domain this week` · `Plan trip next week` · `Hike this weekend` | Friday · next Monday · Saturday |

Dates are English phrases, read by macOS's date detection plus a few rules for what it misses.

**From Text…** (when Add from Text is on): paste an email, chat or schedule and tick the events and reminders it
finds. Only dates that appear in the text are used, and nothing is added until you tick it.

## Meetings

**Join** appears on meetings with a Zoom, Google Meet, Microsoft Teams, Webex, FaceTime or Slack Huddle link,
from 15 minutes before they start. ⌥⌘J joins the current one from any app. Zoom and Teams open in their desktop
apps when installed (Settings → General).

The full-screen alert (Settings → Alerts) covers every screen when a meeting starts, or at any of the times you
pick before it. Return joins, Esc dismisses, and "remind me in 1/2/5 min" brings it back. Joining from the alert
stops the rest for that meeting. It can also close by itself after a while, showing a countdown.

## Keyboard

| Key | Action |
|---|---|
| ⌥⌘N | Quick add (from any app) |
| ⌥⌘J | Join the current meeting (from any app) |
| ← → ↑ ↓ | Move the selected day |
| ⌘← ⌘→ | Previous / next month |
| T | Today |
| ⌘N · ⌘, · ⌘P | New · Settings · Keep the popover open |

Change the global shortcuts in Settings → Shortcuts.

## Right-click

- **An event:** join, copy the meeting link or details, open it in Calendar, or **Meeting Is Over** when it ends
  early (it leaves the menu bar, and an end-of-meeting Shortcut runs).
- **A reminder:** open it in Reminders, mark it done, or remind me later (in an hour, this evening, tomorrow,
  next week). A plain click opens it in Reminders.

## Settings

Everything below is off until you turn it on.

| Feature | Where | What it does |
|---|---|---|
| Meeting brief | Alerts | A small panel before a meeting: who's coming, links and notes. Swipe it right to close. |
| Notes summaries | Alerts → Meeting brief | Apple Intelligence sums up long invitation notes, marked as a summary |
| Alert times · snooze | Alerts | Alert at several times (15–1 min before, at the start); "remind me in 1/2/5 min" |
| Close the alert automatically | Alerts | After 15 s–5 min, with a countdown on the alert |
| Shortcuts on meetings | Alerts | Run a Shortcut when a meeting starts and ends, e.g. Do Not Disturb |
| Add from Text | General | "From Text…" in quick add; read by Apple Intelligence or date detection |
| Keep the current meeting | Menu Bar | `Standup · 3m left → Design review`, with a red timer near the end |
| Back-to-back marks | Calendar | An orange mark on meetings with no break before them |
| Second time zone | Calendar | Meeting times and a clock for another city; Free times can use it |
| Invitations | Calendar | Dims unanswered and "maybe" meetings and counts invitations waiting for you |
| Free times | Calendar | A popover button that copies your open slots for the next working days |

The popover uses macOS's Liquid Glass. To make it more opaque, turn on *System Settings → Accessibility →
Display → Reduce Transparency*.
