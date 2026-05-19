#!/usr/bin/env ruby

require "cgi"
require "date"
require "json"
require "open-uri"
require "time"

ROOT = File.expand_path("..", __dir__)
OUTPUT_PATH = File.join(ROOT, "london-masjids.json")
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
    id: "mac_westmount",
    name: "MAC Westmount Centre",
    short_name: "MAC Westmount",
    address: "312 Commissioners Rd W Unit 5, London, ON N6J 1Y3",
    lat: 42.9554,
    lng: -81.2766,
    phone: "+1-519-936-2304",
    source_url: "https://centres.macnet.ca/westmount/",
    source_type: "mac_official"
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

def fetch_html(url)
  URI.open(url, "User-Agent" => USER_AGENT, read_timeout: 30).read
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
  jumuah_dhuhr_time = nil

  prayer_items_from(html).each do |item|
    title = title_from(item)
    key = PRAYER_TITLES[title]
    times = time_values_from(item)
    if key
      raise "#{title} is missing iqamah time." if times.length < 2

      jamaat[key] = times[1]
    elsif jumuah_title?(title)
      raise "#{title} is missing iqamah time." if times.empty?

      jumuah_dhuhr_time ||= times[1] || times[0]
    end
  end

  jamaat["dhuhr"] ||= jumuah_dhuhr_time

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

def mac_official_iqamah_times_from(html)
  jamaat = {}
  html.scan(
    /<div class="prayer-time prayer-(fajr|dhuhr|asr|maghrib|isha)[^"]*"[^>]*>.*?<div class="prayer-jamaat">([^<]+)<\/div>.*?<\/div>\s*<!-- END of prayer time-->/m
  ).each do |key, time|
    jamaat[key] = time_text_to_24h(CGI.unescapeHTML(time))
  end

  missing = REQUIRED_PRAYER_KEYS - jamaat.keys
  raise "Missing MAC official iqamah values: #{missing.join(", ")}" unless missing.empty?

  ordered_prayer_times(jamaat)
end

def mac_official_jummah_times_from(html)
  jummah_section = html[/<h2[^>]*>\s*Jummah\s*<\/h2>(.*?)<div class="elementor-element elementor-element-78312260/m, 1]
  raise "Could not find MAC official Jummah section." unless jummah_section

  times = jummah_section.scan(
    /<h2[^>]*>\s*(?:1st|2nd)\s+Prayer\s*<\/h2>.*?<h2[^>]*>\s*(\d{1,2}:\d{2}\s*(?:AM|PM))\s*<\/h2>/mi
  ).flatten.map { |time| time_text_to_24h(CGI.unescapeHTML(time)) }.uniq
  raise "Could not find MAC official Jummah times." if times.empty?

  times
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
  match = value.match(/\A\d{2}:\d{2}\z/)
  raise "#{label} is not HH:mm: #{value.inspect}" unless match

  hour, minute = value.split(":").map(&:to_i)
  raise "#{label} hour is invalid: #{value.inspect}" unless hour.between?(0, 23)
  raise "#{label} minute is invalid: #{value.inspect}" unless minute.between?(0, 59)
end

def validate_record!(record)
  %w[id name short_name address data_source source_url jamaat_times jummah_times last_verified].each do |key|
    value = record.fetch(key)
    raise "#{record["id"]} has blank #{key}." if value.respond_to?(:empty?) && value.empty?
  end

  REQUIRED_PRAYER_KEYS.each do |key|
    validate_time!(record.fetch("jamaat_times").fetch(key), "#{record["id"]}.#{key}")
  end

  record.fetch("jummah_times").each do |time|
    validate_time!(time, "#{record["id"]}.jummah")
  end

  return unless record["jamaat_schedule"]

  schedule = record.fetch("jamaat_schedule")
  raise "#{record["id"]}.jamaat_schedule must be an object." unless schedule.is_a?(Hash)

  schedule.each do |date_key, times|
    Date.iso8601(date_key)
    raise "#{record["id"]}.jamaat_schedule.#{date_key} must be an object." unless times.is_a?(Hash)

    REQUIRED_PRAYER_KEYS.each do |key|
      validate_time!(times.fetch(key), "#{record["id"]}.jamaat_schedule.#{date_key}.#{key}")
    end
  rescue Date::Error
    raise "#{record["id"]}.jamaat_schedule has invalid date key #{date_key.inspect}."
  end
end

def build_record(config, verified_at, date: london_today)
  source_type = config.fetch(:source_type)
  source_url = source_type == "lmm_official" ? london_mosque_monthly_url(date) : config.fetch(:source_url)
  html = fetch_html(source_url)
  jamaat_schedule = nil
  jamaat_times =
    case source_type
    when "lmm_official"
      jamaat_schedule = london_mosque_official_monthly_schedule_from(html, date)
      jamaat_schedule.fetch(date.iso8601)
    when "mac_official"
      mac_official_iqamah_times_from(html)
    else
      iqamah_times_from(html)
    end
  jummah_times =
    case source_type
    when "lmm_official"
      london_mosque_jummah_times_from(fetch_html(config.fetch(:jummah_source_url)))
    when "mac_official"
      mac_official_jummah_times_from(html)
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
    "source_id" => nil,
    "jamaat_times" => jamaat_times,
    "jummah_times" => jummah_times,
    "khateeb" => nil,
    "last_verified" => verified_at
  }
  if jamaat_schedule
    record["schedule_month"] = date.strftime("%Y-%m")
    record["jamaat_schedule"] = jamaat_schedule
  end
  raise "#{record["id"]} has no Jummah iqamah times." if record["jummah_times"].empty?

  validate_record!(record)
  record
rescue StandardError => e
  raise "Failed to build #{config.fetch(:id)} from #{source_url}: #{e.message}"
end

def generate_data(verified_at = Time.now.utc.iso8601, date: london_today)
  {
    "version" => 2,
    "last_updated" => verified_at,
    "mosques" => MOSQUES.map { |config| build_record(config, verified_at, date: date) }
  }
end

def write_data(data)
  File.write(OUTPUT_PATH, "#{JSON.pretty_generate(data)}\n")
  puts "Wrote #{OUTPUT_PATH}"
  data.fetch("mosques").each do |mosque|
    times = mosque.fetch("jamaat_times").map { |key, value| "#{key}=#{value}" }.join(", ")
    puts "#{mosque.fetch("short_name")}: #{times}; Jummah #{mosque.fetch("jummah_times").join(", ")}"
  end
end

if $PROGRAM_NAME == __FILE__
  write_data(generate_data)
end
