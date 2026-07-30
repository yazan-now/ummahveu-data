# UmmahVeu London Masjid Data

Public data feed for UmmahVeu's London, Ontario local mosque iqamah/Jummah
times.

This repository publishes:

```text
london-masjids.json
```

Expected CDN URL:

```text
https://cdn.jsdelivr.net/gh/yazan-now/ummahveu-data@main/london-masjids.json
```

## Source Policy

- Do not estimate iqamah or Jummah times.
- The updater reads the displayed `Iqamah` / `Jumuah` values from each mosque's
  approved public source page.
- London Muslim Mosque uses the official London Mosque monthly schedule at
  `https://www.londonmosque.ca/page/pray_time/monthly/YYYY-MM` and Friday-prayer page at
  `https://www.londonmosque.ca/friday-prayers`.
- The LMM record includes a `jamaat_schedule` map for the whole official month,
  while `jamaat_times` remains the current-day row for older app builds.
- MAC Westmount uses the official MAC Westmount page at
  `https://centres.macnet.ca/westmount/`.
- MAC Hyde Park and Muslim Wellness use their public Masjidbox pages.
- If a source page cannot be fetched or parsed, the updater fails instead of
  publishing guessed times.
- Every candidate must contain all five regular daily prayers in chronological
  order, plus a separate chronological Jummah list. Eid, Taraweeh, and other
  special cards are not treated as regular daily prayers.
- Each source fetch is attempted three times. If one source remains unavailable,
  its last verified record is carried forward; if every source fails, the
  published file is left untouched.

## Mosques In This Feed

- London Muslim Mosque
- MAC Westmount Centre
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
