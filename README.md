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
- MAC Westmount uses the official MAC Westmount page at
  `https://centres.macnet.ca/westmount/`.
- London Muslim Mosque, MAC Hyde Park, and Muslim Wellness use their public
  Masjidbox pages.
- If a source page cannot be fetched or parsed, the updater fails instead of
  publishing guessed times.

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
