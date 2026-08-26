# UmmahVeu London Masjid Data

Public data feed for UmmahVeu's London, Ontario local mosque iqamah/Jummah
times.

This repository publishes:

```text
london-masjids.json
```

Canonical live feed URL:

```text
https://raw.githubusercontent.com/yazan-now/ummahveu-data/main/london-masjids.json
```

The raw GitHub `main` route is the runtime and readiness authority. Mutable
jsDelivr branch URLs are retired because an edge may continue serving an older
catalog after `main` advances. Commit-pinned immutable CDN URLs may be used only
to reproduce historical publication evidence, never as the live schedule.

## Source Policy

- Do not estimate iqamah or Jummah times.
- The updater reads the displayed `Iqamah` / `Jumuah` values from each mosque's
  approved public source page.
- London Muslim Mosque uses the official London Mosque monthly schedule at
  `https://www.londonmosque.ca/page/pray_time/monthly/YYYY-MM` and Friday-prayer page at
  `https://www.londonmosque.ca/friday-prayers`.
- The LMM record includes a `jamaat_schedule` map for the whole official month,
  while `jamaat_times` remains the current-day row for older app builds.
- MAC Noor Gardens uses its official centre page at
  `https://centres.macnet.ca/macnoorgardens/` to verify identity and address.
- MAC Noor Gardens remains metadata-only with daily iqamah and Jummah
  unavailable. The feed never derives current times from an old timetable.
- MAC Hyde Park and Muslim Wellness use their public Masjidbox pages.
- If a source page cannot be fetched or parsed, the updater fails instead of
  publishing guessed times.
- Every timed candidate must contain all five regular daily prayers in
  chronological order, plus a separate chronological Jummah list. The explicit
  MAC Noor Gardens metadata-only record instead carries `jummah_status` as
  `unavailable`, `jamaat_times` as `null`, and an empty Jummah list. Eid,
  Taraweeh, and other special cards are not treated as regular daily prayers.
- Each source fetch is attempted three times. If one source remains unavailable,
  its last verified record is carried forward; if every source fails, the
  published file is left untouched.

## Mosques In This Feed

- London Muslim Mosque
- MAC Noor Gardens
- MAC Hyde Park Masjid
- Muslim Wellness Network

## Update Locally

```bash
ruby scripts/update_london_masjids.rb
```

The GitHub Actions workflow runs the same command daily and can also be
triggered manually from GitHub.

## Emergency Manual Override

`manual-overrides.json` is the source-controlled emergency override. An
override must name one mosque, include an exact start and end date, a reason,
and a verification timestamp. It may replace the five regular jamaat times,
the separate Jummah list, or both. The same validation rules run after the
override is applied, and an override stops applying automatically after its
`ends_on` date.

Keep the file empty during normal operation:

```json
{
  "version": 1,
  "overrides": []
}
```

GitHub Actions failure-email delivery remains controlled by each repository
watcher's GitHub notification settings; this repository does not store email
addresses or mail credentials.
