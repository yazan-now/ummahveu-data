#!/usr/bin/env ruby

require "cgi"
require "date"
require "json"
require "open-uri"
require "tempfile"
require "time"

ROOT = File.expand_path("..", __dir__)
OUTPUT_PATH = File.join(ROOT, "london-masjids.json")
MANUAL_OVERRIDES_PATH = File.join(ROOT, "manual-overrides.json")
USER_AGENT = "UmmahVeuDataBot/1.0 (+https://github.com/yazan-now/ummahveu-data)"
LONDON_TIME_ZONE = "America/Toronto"
LONDON_MOSQUE_MONTHLY_BASE_URL = "https://www.londonmosque.ca/page/pray_time/monthly"
LONDON_MOSQUE_FRIDAY_URL = "https://www.londonmosque.ca/friday-prayers"
PRAYER_TITLES = {
  "Fajr" => "fajr",
  "Dhuhr" => "dhuhr",
  "Zuhr" => "dhuhr",
  "Asr" => "asr",
  "Maghrib" => "maghrib",
  "Isha" => "isha"
}.freeze
REQUIRED_PRAYER_KEYS = PRAYER_TITLES.values.uniq.freeze
NOOR_GARDENS_ID = "mac_noor_gardens"
NOOR_GARDENS_SOURCE_ID = "macnoorgardens"

MOSQUES = [
  {
    id: "lmm",
    name: "London Muslim Mosque",
    short_name: "LMM",
    address: "151 Oxford St W, London, ON N6H 1S1",
    lat: 42.9849,
    lng: -81.2453,
    phone: "+1-519-439-9451",
    source_url: LONDON_MOSQUE_MONTHLY_BASE_URL,
    jummah_source_url: LONDON_MOSQUE_FRIDAY_URL,
    source_type: "lmm_official"
  },
  {
    id: NOOR_GARDENS_ID,
    name: "MAC Noor Gardens",
    short_name: "MAC Noor Gardens",
    address: "457 Southdale Rd W, London, ON N6P 1M7",
    lat: 42.937182552938935,
    lng: -81.285658954204123,
    phone: "+1-519-936-2304",
    source_url: "https://centres.macnet.ca/macnoorgardens/",
    source_id: NOOR_GARDENS_SOURCE_ID,
    source_type: "noor_official"
  },
  {
    id: "mac_hyde_park",
    name: "MAC Hyde Park Masjid",
    short_name: "MAC Hyde Park",
    address: "1175 Hyde Park Rd, Unit 9, London, ON",
    lat: 43.0226,
    lng: -81.3340,
    phone: "+1-519-474-2588",
    source_url: "https://masjidbox.com/prayer-times/mac-london",
    source_type: "masjidbox"
  },
  {
    id: "muslim_wellness",
    name: "Muslim Wellness Network",
    short_name: "Muslim Wellness",
    address: "990 Gainsborough Rd, London, ON N6H 5L4",
    lat: 43.0008,
    lng: -81.3221,
    phone: "+1-519-914-3377",
    source_url: "https://masjidbox.com/prayer-times/muslim-wellness",
    source_type: "masjidbox"
  }
].freeze

# A single flaky host used to abort the entire run: `read_timeout` does not
# cover CONNECTION setup, so a Net::OpenTimeout on one mosque's site killed the
# whole dataset (2026-07-28, centres.macnet.ca). Bound both phases and retry.
FETCH_ATTEMPTS = 3

def fetch_html(url)
  attempt = 0
  begin
    attempt += 1
    URI.open(url, "User-Agent" => USER_AGENT, open_timeout: 15, read_timeout: 30).read
  rescue StandardError => e
    raise if attempt >= FETCH_ATTEMPTS

    warn "  retry #{attempt}/#{FETCH_ATTEMPTS - 1} for #{url}: #{e.class}: #{e.message}"
    sleep(2 * attempt)
    retry
  end
end

# Last published dataset, keyed by mosque id, used to ride out a single site
# being briefly unreachable.
def previous_records
  return {} unless File.exist?(OUTPUT_PATH)

  JSON.parse(File.read(OUTPUT_PATH))
      .fetch("mosques", [])
      .each_with_object({}) do |mosque, records|
        validate_fallback_record!(mosque)
        records[mosque.fetch("id")] = mosque
      rescue StandardError => e
        warn "Ignoring invalid previous record #{mosque["id"].inspect}: #{e.message}"
      end
rescue StandardError => e
  warn "Could not read previous #{OUTPUT_PATH}: #{e.message}"
  {}
end

# Carry a mosque forward when its site is down.
#
# CRITICAL: `jamaat_times` is TODAY'S times. Reusing yesterday's would show the
# wrong prayer time, which is worse than showing none — the iOS app treats a
# missing value as "unavailable" and says so (jamaatTimes is optional and
# LondonMasjidRemoteModels.swift:124 already prefers the date-keyed schedule).
# So: if the stored monthly schedule covers today, today's times are still
# genuinely correct and are re-derived. Otherwise they are dropped, and only
# the stable fields (address, phone, Jummah) carry over.
def stale_fallback(config, previous, date:)
  prior = previous[config.fetch(:id)]
  return nil unless prior

  record = prior.dup
  if config.fetch(:id) == NOOR_GARDENS_ID
    record["jamaat_times"] = nil
    record["jummah_times"] = []
    record["jummah_status"] = "unavailable"
    record["stale_source"] = true
    return record
  end

  schedule = record["jamaat_schedule"]
  today_key = date.iso8601
  if schedule.is_a?(Hash) && schedule[today_key]
    record["jamaat_times"] = schedule.fetch(today_key)
    record["stale_source"] = false
  else
    record["jamaat_times"] = nil
    record["stale_source"] = true
  end
  record
end

def london_today
  original_tz = ENV["TZ"]
  ENV["TZ"] = LONDON_TIME_ZONE
  Date.today
ensure
  ENV["TZ"] = original_tz
end

def london_mosque_monthly_url(date)
  "#{LONDON_MOSQUE_MONTHLY_BASE_URL}/#{date.strftime("%Y-%m")}"
end

def text_from_html(fragment)
  with_colons = fragment.gsub(
    /<div class="styles__Wrapper-sc-1rm9q09-0[^"]*"[^>]*><\/div>/,
    ":"
  )
  CGI.unescapeHTML(with_colons.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip)
end

def time_fragment_to_24h(fragment, ampm)
  compact = "#{text_from_html(fragment)}#{ampm}".gsub(/\s+/, "")
  match = compact.match(/\A(\d{1,2}):(\d{2})(AM|PM)\z/i)
  raise "Could not parse time fragment: #{compact.inspect}" unless match

  hour = match[1].to_i
  minute = match[2].to_i
  period = match[3].upcase
  hour = 0 if period == "AM" && hour == 12
  hour += 12 if period == "PM" && hour < 12
  format("%02d:%02d", hour, minute)
end

def time_text_to_24h(text)
  match = text.strip.match(/\A(\d{1,2}):(\d{2})\s*(am|pm)\z/i)
  raise "Could not parse time text: #{text.inspect}" unless match

  hour = match[1].to_i
  minute = match[2].to_i
  period = match[3].upcase
  hour = 0 if period == "AM" && hour == 12
  hour += 12 if period == "PM" && hour < 12
  format("%02d:%02d", hour, minute)
end

def time_values_from(fragment)
  fragment.scan(/<div class="time[^"]*"[^>]*>(.*?)<sup class="ampm"[^>]*>(AM|PM)<\/sup><\/div>/m)
          .map { |body, ampm| time_fragment_to_24h(body, ampm) }
end

def title_from(item_html)
  raw = item_html[/<div class="title[^"]*"[^>]*>(.*?)<\/div>/m, 1]
  raise "Prayer card is missing a title." unless raw

  text_from_html(raw)
end

def jumuah_title?(title)
  normalized = title.downcase.gsub(/[^a-z]/, "")
  normalized.start_with?("jumuah", "jummah")
end

def ordered_prayer_times(jamaat)
  REQUIRED_PRAYER_KEYS.each_with_object({}) do |key, ordered|
    ordered[key] = jamaat.fetch(key)
  end
end

def prayer_items_from(html)
  html.scan(
    /<div class="styles__Item-sc-1h272ay-1\b[^"]*"[^>]*>(.*?)(?=<div class="styles__Item-sc-1h272ay-1\b|<div class="styles__Wrapper-sc-fn1c8y-0\b)/m
  ).flatten
end

def iqamah_times_from(html)
  jamaat = {}

  prayer_items_from(html).each do |item|
    title = title_from(item)
    key = PRAYER_TITLES[title]
    times = time_values_from(item)
    if key
      raise "#{title} is missing iqamah time." if times.length < 2

      jamaat[key] = times[1]
    end
  end

  missing = REQUIRED_PRAYER_KEYS - jamaat.keys
  raise "Missing iqamah values: #{missing.join(", ")}" unless missing.empty?

  ordered_prayer_times(jamaat)
end

def jummah_times_from(html)
  times = html.scan(/<div class="iqamah-time[^"]*"[^>]*>(.*?)<sup class="ampm"[^>]*>(AM|PM)<\/sup><\/div>/m)
              .map { |body, ampm| time_fragment_to_24h(body, ampm) }
              .uniq
  return times unless times.empty?

  html.scan(/<div class="athan-time[^"]*"[^>]*>(.*?)<sup class="ampm"[^>]*>(AM|PM)<\/sup><\/div>/m)
      .map { |body, ampm| time_fragment_to_24h(body, ampm) }
      .uniq
end

def verify_noor_gardens_metadata!(html)
  text = text_from_html(html)
  required_fragments = [
    "MAC Noor Gardens",
    "457 Southdale Rd W",
    "N6P 1M7"
  ]
  missing = required_fragments.reject { |fragment| text.include?(fragment) }
  return if missing.empty?

  raise "MAC Noor Gardens official page is missing verified metadata: #{missing.join(", ")}"
end

def noor_gardens_schedule_from(html, date)
  verify_noor_gardens_metadata!(html)

  wrapper = html[
    /<div class="dpt-horizontal-wrapper\b[^"]*"[^>]*>(.*?)<\/div>\s*<!-- END of wrapper container-->/m,
    1
  ]
  raise "MAC Noor Gardens official page is missing the daily prayer schedule." unless wrapper

  date_fragments = wrapper.scan(/<h3 class="date\b[^"]*"[^>]*>(.*?)<\/h3>/m).flatten
  raise "MAC Noor Gardens schedule must display exactly one date." unless date_fragments.length == 1

  date_text = text_from_html(date_fragments.first)
  unless date_text.match?(/\A(?:January|February|March|April|May|June|July|August|September|October|November|December) \d{1,2}, \d{4}\z/)
    raise "MAC Noor Gardens schedule date is malformed: #{date_text.inspect}"
  end

  displayed_date = Date.strptime(date_text, "%B %d, %Y")
  unless displayed_date == date
    raise "MAC Noor Gardens displayed date #{displayed_date.iso8601} does not match #{date.iso8601}."
  end

  athan_times = {}
  jamaat_times = {}
  REQUIRED_PRAYER_KEYS.each do |key|
    cards = wrapper.scan(
      /<div class="prayer-time prayer-#{Regexp.escape(key)}\b[^"]*"[^>]*>(.*?)<\/div>\s*<!-- END of prayer time-->/m
    ).flatten
    raise "MAC Noor Gardens must display exactly one #{key} row." unless cards.length == 1

    card = cards.first
    starts = card.scan(/<div\s+class="prayer-start"[^>]*>(.*?)<\/div>/m).flatten
    jamaats = card.scan(/<div\s+class="prayer-jamaat"[^>]*>(.*?)<\/div>/m).flatten
    unless starts.length == 1 && jamaats.length == 1
      raise "MAC Noor Gardens #{key} row must contain one Athan and one Jamaat time."
    end

    athan_times[key] = time_text_to_24h(text_from_html(starts.first))
    jamaat_times[key] = time_text_to_24h(text_from_html(jamaats.first))
  end

  athan_times = ordered_prayer_times(athan_times)
  jamaat_times = ordered_prayer_times(jamaat_times)
  validate_daily_times!(athan_times, "#{NOOR_GARDENS_ID}.athan_times")
  validate_daily_times!(jamaat_times, "#{NOOR_GARDENS_ID}.jamaat_times")
  REQUIRED_PRAYER_KEYS.each do |key|
    next if minutes_since_midnight(athan_times.fetch(key), "#{NOOR_GARDENS_ID}.athan_times.#{key}") <=
            minutes_since_midnight(jamaat_times.fetch(key), "#{NOOR_GARDENS_ID}.jamaat_times.#{key}")

    raise "MAC Noor Gardens #{key} Jamaat time precedes its Athan time."
  end

  jummah_rows = html.scan(
    /<h2\b[^>]*>\s*Prayer\s*1:\s*(\d{1,2}:\d{2}\s*(?:AM|PM))\s*<br\s*\/?>(?:\s|&nbsp;)*Prayer\s*2:\s*(\d{1,2}:\d{2}\s*(?:AM|PM))\s*<\/h2>/im
  )
  raise "MAC Noor Gardens must display exactly one two-prayer Jummah block." unless jummah_rows.length == 1

  jummah_times = jummah_rows.first.map { |time| time_text_to_24h(time) }
  validate_jummah_times!(jummah_times, "#{NOOR_GARDENS_ID}.jummah_times")

  {
    "date" => displayed_date.iso8601,
    "athan_times" => athan_times,
    "jamaat_times" => jamaat_times,
    "jummah_times" => jummah_times
  }
rescue ArgumentError => e
  raise "MAC Noor Gardens schedule date is invalid: #{e.message}"
end

def london_mosque_official_iqamah_times_from(html, date)
  schedule = london_mosque_official_monthly_schedule_from(html, date)
  schedule.fetch(date.iso8601) do
    raise "Could not find London Mosque row for #{date.iso8601}."
  end
end

def london_mosque_official_monthly_schedule_from(html, date)
  schedule = {}
  rows = html.scan(/<tr[^>]*>(.*?)<\/tr>/m).map(&:first)
  rows.each do |row|
    cells = row.scan(/<td\b[^>]*>(.*?)<\/td>/m).map(&:first)
    next if cells.empty?

    day = london_mosque_day_from_cell(cells.first)
    next unless day
    raise "London Mosque row for day #{day} has unexpected column count." if cells.length < 7

    date_key = Date.new(date.year, date.month, day).iso8601
    schedule[date_key] = ordered_prayer_times(
      "fajr" => london_mosque_second_time_from_cell(cells[1], "Fajr"),
      "dhuhr" => london_mosque_second_time_from_cell(cells[3], "Zuhr"),
      "asr" => london_mosque_second_time_from_cell(cells[4], "Asr"),
      "maghrib" => london_mosque_second_time_from_cell(cells[5], "Maghrib"),
      "isha" => london_mosque_second_time_from_cell(cells[6], "Isha")
    )
  end

  raise "London Mosque monthly schedule is empty." if schedule.empty?

  expected_dates = (1..Date.new(date.year, date.month, -1).day).map do |day|
    Date.new(date.year, date.month, day).iso8601
  end
  missing = expected_dates - schedule.keys
  raise "London Mosque monthly schedule is missing date(s): #{missing.join(", ")}" unless missing.empty?

  schedule.sort.to_h
end

def london_mosque_day_from_cell(cell_html)
  text_from_html(cell_html)[/\b(\d{1,2})\b/, 1]&.to_i
end

def london_mosque_second_time_from_cell(cell_html, label)
  times = text_from_html(cell_html).scan(/\d{1,2}:\d{2}\s*(?:AM|PM)/i)
  raise "London Mosque #{label} cell is missing iqamah time." if times.length < 2

  time_text_to_24h(times[1])
end

def london_mosque_jummah_times_from(html)
  times = text_from_html(html)
          .scan(/(?:First|Second)\s+Khutbah\s+(\d{1,2}:\d{2}\s*(?:AM|PM))/i)
          .flatten
          .map { |time| time_text_to_24h(time) }
          .uniq
  raise "Could not find London Mosque Jummah times." if times.empty?

  times
end

def validate_time!(value, label)
  raise "#{label} is not HH:mm: #{value.inspect}" unless value.is_a?(String) && value.match?(/\A\d{2}:\d{2}\z/)

  hour, minute = value.split(":").map(&:to_i)
  raise "#{label} hour is invalid: #{value.inspect}" unless hour.between?(0, 23)
  raise "#{label} minute is invalid: #{value.inspect}" unless minute.between?(0, 59)
end

def minutes_since_midnight(value, label)
  validate_time!(value, label)
  hour, minute = value.split(":").map(&:to_i)
  (hour * 60) + minute
end

def validate_daily_times!(times, label)
  raise "#{label} must be an object." unless times.is_a?(Hash)

  missing = REQUIRED_PRAYER_KEYS - times.keys
  extras = times.keys - REQUIRED_PRAYER_KEYS
  raise "#{label} is missing: #{missing.join(", ")}" unless missing.empty?
  raise "#{label} has unexpected prayers: #{extras.join(", ")}" unless extras.empty?

  minutes = REQUIRED_PRAYER_KEYS.map do |key|
    minutes_since_midnight(times.fetch(key), "#{label}.#{key}")
  end
  return if minutes.each_cons(2).all? { |earlier, later| earlier < later }

  raise "#{label} is not chronological (Fajr < Dhuhr < Asr < Maghrib < Isha)."
end

def validate_jummah_times!(times, label)
  raise "#{label} must be a non-empty array." unless times.is_a?(Array) && !times.empty?

  minutes = times.map.with_index do |time, index|
    minutes_since_midnight(time, "#{label}[#{index}]")
  end
  return if minutes.uniq.length == minutes.length &&
            minutes.each_cons(2).all? { |earlier, later| earlier < later }

  raise "#{label} must contain distinct times in chronological order."
end

def validate_schedule!(schedule, label)
  raise "#{label} must be an object." unless schedule.is_a?(Hash)

  schedule.each do |date_key, times|
    Date.iso8601(date_key)
    validate_daily_times!(times, "#{label}.#{date_key}")
  rescue ArgumentError
    raise "#{label} has invalid date key #{date_key.inspect}."
  end
end

def validate_record!(record)
  if record["id"] == NOOR_GARDENS_ID
    validate_noor_gardens_record!(record)
    return
  end

  %w[id name short_name address data_source source_url jamaat_times jummah_times last_verified].each do |key|
    value = record.fetch(key)
    raise "#{record["id"]} has blank #{key}." if value.nil? || (value.respond_to?(:empty?) && value.empty?)
  end

  validate_daily_times!(record.fetch("jamaat_times"), "#{record["id"]}.jamaat_times")
  validate_jummah_times!(record.fetch("jummah_times"), "#{record["id"]}.jummah_times")
  Time.iso8601(record.fetch("last_verified"))

  return unless record["jamaat_schedule"]

  validate_schedule!(record.fetch("jamaat_schedule"), "#{record["id"]}.jamaat_schedule")
end

def validate_fallback_record!(record)
  if record["id"] == NOOR_GARDENS_ID
    validate_noor_gardens_record!(record)
    return
  end

  %w[id name short_name address data_source source_url jummah_times last_verified].each do |key|
    value = record.fetch(key)
    raise "#{record["id"]} has blank #{key}." if value.nil? || (value.respond_to?(:empty?) && value.empty?)
  end
  Time.iso8601(record.fetch("last_verified"))
  validate_jummah_times!(record.fetch("jummah_times"), "#{record["id"]}.jummah_times")
  if record["jamaat_times"]
    validate_daily_times!(record.fetch("jamaat_times"), "#{record["id"]}.jamaat_times")
  elsif record["stale_source"] != true
    raise "#{record["id"]} has no daily schedule and is not marked as a stale source."
  end
  validate_schedule!(record.fetch("jamaat_schedule"), "#{record["id"]}.jamaat_schedule") if record["jamaat_schedule"]
end

def validate_noor_gardens_record!(record)
  config = MOSQUES.find { |mosque| mosque.fetch(:id) == NOOR_GARDENS_ID }
  expected = {
    "id" => config.fetch(:id),
    "name" => config.fetch(:name),
    "short_name" => config.fetch(:short_name),
    "address" => config.fetch(:address),
    "lat" => config.fetch(:lat),
    "lng" => config.fetch(:lng),
    "phone" => config.fetch(:phone),
    "data_source" => "official_website",
    "source_url" => config.fetch(:source_url),
    "source_id" => config.fetch(:source_id),
    "khateeb" => nil
  }
  expected.each do |key, value|
    raise "#{NOOR_GARDENS_ID} has invalid #{key}." unless record.fetch(key) == value
  end
  raise "#{NOOR_GARDENS_ID} must not publish a daily schedule." if record["jamaat_schedule"] || record["schedule_month"]
  raise "#{NOOR_GARDENS_ID} must not accept a manual schedule override." if record["manual_override"]
  if record["stale_source"] == true
    raise "#{NOOR_GARDENS_ID} stale fallback must not publish daily times." unless record["jamaat_times"].nil?
    raise "#{NOOR_GARDENS_ID} stale fallback must not publish Jummah times." unless record["jummah_times"] == []
    raise "#{NOOR_GARDENS_ID} stale fallback must be unavailable." unless record["jummah_status"] == "unavailable"
  else
    raise "#{NOOR_GARDENS_ID} stale_source must be true when present." if record.key?("stale_source")
    validate_daily_times!(record.fetch("jamaat_times"), "#{NOOR_GARDENS_ID}.jamaat_times")
    validate_jummah_times!(record.fetch("jummah_times"), "#{NOOR_GARDENS_ID}.jummah_times")
    raise "#{NOOR_GARDENS_ID} must publish exactly two Jummah times." unless record.fetch("jummah_times").length == 2
    raise "#{NOOR_GARDENS_ID} must not be unavailable after a valid refresh." if record.key?("jummah_status")
  end
  Time.iso8601(record.fetch("last_verified"))
end

def manual_overrides(path = MANUAL_OVERRIDES_PATH)
  return [] unless File.exist?(path)

  data = JSON.parse(File.read(path))
  raise "#{path} must use version 1." unless data.fetch("version") == 1

  overrides = data.fetch("overrides")
  raise "#{path} overrides must be an array." unless overrides.is_a?(Array)

  overrides.each { |override| validate_manual_override!(override) }
  overrides
end

def validate_manual_override!(override)
  %w[mosque_id starts_on ends_on reason verified_at].each do |key|
    value = override.fetch(key)
    raise "Manual override has blank #{key}." if value.nil? || (value.respond_to?(:empty?) && value.empty?)
  end
  raise "Unknown manual override mosque #{override["mosque_id"]}." unless MOSQUES.any? { |mosque| mosque[:id] == override["mosque_id"] }
  if override["mosque_id"] == NOOR_GARDENS_ID
    raise "MAC Noor Gardens uses only its official homepage and cannot accept a schedule override."
  end

  starts_on = Date.iso8601(override.fetch("starts_on"))
  ends_on = Date.iso8601(override.fetch("ends_on"))
  raise "Manual override ends before it starts." if ends_on < starts_on

  Time.iso8601(override.fetch("verified_at"))
  has_daily = override.key?("jamaat_times")
  has_jummah = override.key?("jummah_times")
  raise "Manual override must provide jamaat_times or jummah_times." unless has_daily || has_jummah

  validate_daily_times!(override.fetch("jamaat_times"), "manual_override.jamaat_times") if has_daily
  validate_jummah_times!(override.fetch("jummah_times"), "manual_override.jummah_times") if has_jummah
rescue ArgumentError => e
  raise "Manual override has an invalid date or verified_at: #{e.message}"
end

def apply_manual_overrides(records, overrides, date:)
  active = overrides.select do |override|
    Date.iso8601(override.fetch("starts_on")) <= date &&
      date <= Date.iso8601(override.fetch("ends_on"))
  end
  duplicates = active.group_by { |override| override.fetch("mosque_id") }.select { |_id, rows| rows.length > 1 }
  raise "Multiple active manual overrides for: #{duplicates.keys.join(", ")}." unless duplicates.empty?

  records.map do |record|
    override = active.find { |candidate| candidate.fetch("mosque_id") == record.fetch("id") }
    next record unless override

    overridden = JSON.parse(JSON.generate(record))
    if override.key?("jamaat_times")
      overridden["jamaat_times"] = override.fetch("jamaat_times")
      if overridden["jamaat_schedule"].is_a?(Hash)
        overridden["jamaat_schedule"][date.iso8601] = override.fetch("jamaat_times")
      end
    end
    overridden["jummah_times"] = override.fetch("jummah_times") if override.key?("jummah_times")
    overridden["last_verified"] = override.fetch("verified_at")
    overridden.delete("stale_source")
    overridden["manual_override"] = {
      "starts_on" => override.fetch("starts_on"),
      "ends_on" => override.fetch("ends_on"),
      "reason" => override.fetch("reason"),
      "verified_at" => override.fetch("verified_at")
    }
    validate_record!(overridden)
    overridden
  end
end

def build_record(config, verified_at, date: london_today)
  source_type = config.fetch(:source_type)
  source_url = source_type == "lmm_official" ? london_mosque_monthly_url(date) : config.fetch(:source_url)
  html = fetch_html(source_url)
  jamaat_schedule = nil
  noor_schedule = nil
  jamaat_times =
    case source_type
    when "lmm_official"
      jamaat_schedule = london_mosque_official_monthly_schedule_from(html, date)
      jamaat_schedule.fetch(date.iso8601)
    when "noor_official"
      noor_schedule = noor_gardens_schedule_from(html, date)
      noor_schedule.fetch("jamaat_times")
    else
      iqamah_times_from(html)
    end
  jummah_times =
    case source_type
    when "lmm_official"
      london_mosque_jummah_times_from(fetch_html(config.fetch(:jummah_source_url)))
    when "noor_official"
      noor_schedule.fetch("jummah_times")
    else
      jummah_times_from(html)
    end
  record = {
    "id" => config.fetch(:id),
    "name" => config.fetch(:name),
    "short_name" => config.fetch(:short_name),
    "address" => config.fetch(:address),
    "lat" => config.fetch(:lat),
    "lng" => config.fetch(:lng),
    "phone" => config.fetch(:phone),
    "logo_url" => nil,
    "data_source" => source_type == "masjidbox" ? "masjidbox" : "official_website",
    "source_url" => source_url,
    "source_id" => config[:source_id],
    "jamaat_times" => jamaat_times,
    "jummah_times" => jummah_times,
    "khateeb" => nil,
    "last_verified" => verified_at
  }
  if jamaat_schedule
    record["schedule_month"] = date.strftime("%Y-%m")
    record["jamaat_schedule"] = jamaat_schedule
  end
  if record["jummah_times"].empty?
    raise "#{record["id"]} has no Jummah iqamah times."
  end

  validate_record!(record)
  record
rescue StandardError => e
  raise "Failed to build #{config.fetch(:id)} from #{source_url}: #{e.message}"
end

def generate_data(verified_at = Time.now.utc.iso8601, date: london_today, overrides: manual_overrides)
  previous = previous_records
  degraded = []

  mosques = MOSQUES.map do |config|
    build_record(config, verified_at, date: date)
  rescue StandardError => e
    warn "WARN #{config.fetch(:id)}: #{e.message}"
    fallback = stale_fallback(config, previous, date: date)
    raise "#{config.fetch(:id)} failed and there is no previous record to fall back on: #{e.message}" unless fallback

    degraded << config.fetch(:id)
    fallback
  end

  # Everything failing means the run itself is broken (network, a shared
  # dependency), not one flaky site. Fail loudly and leave the published file
  # alone rather than republishing an all-stale dataset as if it were fresh.
  if degraded.size == MOSQUES.size
    raise "Every mosque failed to refresh (#{degraded.join(", ")}); leaving #{OUTPUT_PATH} untouched."
  end

  unless degraded.empty?
    warn "Published with #{degraded.size} degraded mosque(s): #{degraded.join(", ")}"
  end

  mosques = apply_manual_overrides(mosques, overrides, date: date)

  {
    "version" => 2,
    "last_updated" => verified_at,
    "mosques" => mosques
  }
end

def validate_dataset!(data)
  raise "bad version" unless data.fetch("version") == 2
  Time.iso8601(data.fetch("last_updated"))
  mosques = data.fetch("mosques")
  raise "mosques must be an array" unless mosques.is_a?(Array)
  expected_ids = MOSQUES.map { |mosque| mosque.fetch(:id) }.sort
  actual_ids = mosques.map { |mosque| mosque.fetch("id") }.sort
  raise "mosque set changed: #{actual_ids.inspect}" unless actual_ids == expected_ids

  mosques.each { |record| validate_fallback_record!(record) }
end

def write_data(data, output_path: OUTPUT_PATH)
  validate_dataset!(data)
  output_directory = File.dirname(output_path)
  Tempfile.create(["london-masjids", ".json"], output_directory) do |temporary|
    temporary.write("#{JSON.pretty_generate(data)}\n")
    temporary.flush
    temporary.fsync
    File.rename(temporary.path, output_path)
  end
  puts "Wrote #{output_path}"
  data.fetch("mosques").each do |mosque|
    # jamaat_times is nil for a mosque carried forward from the previous run
    # whose site was unreachable and which has no monthly schedule covering
    # today - see stale_fallback. Printing it must not crash the run, or the
    # job still exits non-zero after successfully publishing.
    jamaat = mosque["jamaat_times"]
    times = if jamaat
              jamaat.map { |key, value| "#{key}=#{value}" }.join(", ")
            else
              "unavailable (source down)"
            end
    jummah_values = Array(mosque["jummah_times"])
    jummah = jummah_values.empty? ? "unavailable" : jummah_values.join(", ")
    puts "#{mosque.fetch("short_name")}: #{times}; Jummah #{jummah}"
  end
end

if $PROGRAM_NAME == __FILE__
  write_data(generate_data)
end
