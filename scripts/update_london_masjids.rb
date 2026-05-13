#!/usr/bin/env ruby

require "cgi"
require "json"
require "open-uri"
require "time"

ROOT = File.expand_path("..", __dir__)
OUTPUT_PATH = File.join(ROOT, "london-masjids.json")
USER_AGENT = "UmmahVeuDataBot/1.0 (+https://github.com/yazanali/ummahveu-data)"
PRAYER_TITLES = {
  "Fajr" => "fajr",
  "Dhuhr" => "dhuhr",
  "Asr" => "asr",
  "Maghrib" => "maghrib",
  "Isha" => "isha"
}.freeze

MOSQUES = [
  {
    id: "lmm",
    name: "London Muslim Mosque",
    short_name: "LMM",
    address: "151 Oxford St W, London, ON N6H 1S1",
    lat: 42.9849,
    lng: -81.2453,
    phone: "+1-519-439-9451",
    source_url: "https://masjidbox.com/prayer-times/london-muslim-mosque-1726080054566"
  },
  {
    id: "mac_hyde_park",
    name: "MAC Hyde Park Masjid",
    short_name: "MAC Hyde Park",
    address: "1175 Hyde Park Rd, Unit 9, London, ON",
    lat: 43.0226,
    lng: -81.3340,
    phone: "+1-519-474-2588",
    source_url: "https://masjidbox.com/prayer-times/mac-london"
  },
  {
    id: "muslim_wellness",
    name: "Muslim Wellness Network",
    short_name: "Muslim Wellness",
    address: "990 Gainsborough Rd, London, ON N6H 5L4",
    lat: 43.0008,
    lng: -81.3221,
    phone: "+1-519-914-3377",
    source_url: "https://masjidbox.com/prayer-times/muslim-wellness"
  }
].freeze

def fetch_html(url)
  URI.open(url, "User-Agent" => USER_AGENT, read_timeout: 30).read
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

def time_values_from(fragment)
  fragment.scan(/<div class="time[^"]*"[^>]*>(.*?)<sup class="ampm"[^>]*>(AM|PM)<\/sup><\/div>/m)
          .map { |body, ampm| time_fragment_to_24h(body, ampm) }
end

def title_from(item_html)
  raw = item_html[/<div class="title[^"]*"[^>]*>(.*?)<\/div>/m, 1]
  raise "Prayer card is missing a title." unless raw

  text_from_html(raw)
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
    next unless key

    times = time_values_from(item)
    raise "#{title} is missing iqamah time." if times.length < 2

    jamaat[key] = times[1]
  end

  missing = PRAYER_TITLES.values - jamaat.keys
  raise "Missing iqamah values: #{missing.join(", ")}" unless missing.empty?

  jamaat
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

  PRAYER_TITLES.values.each do |key|
    validate_time!(record.fetch("jamaat_times").fetch(key), "#{record["id"]}.#{key}")
  end

  record.fetch("jummah_times").each do |time|
    validate_time!(time, "#{record["id"]}.jummah")
  end
end

def build_record(config, verified_at)
  html = fetch_html(config.fetch(:source_url))
  record = {
    "id" => config.fetch(:id),
    "name" => config.fetch(:name),
    "short_name" => config.fetch(:short_name),
    "address" => config.fetch(:address),
    "lat" => config.fetch(:lat),
    "lng" => config.fetch(:lng),
    "phone" => config.fetch(:phone),
    "logo_url" => nil,
    "data_source" => "masjidbox",
    "source_url" => config.fetch(:source_url),
    "source_id" => nil,
    "jamaat_times" => iqamah_times_from(html),
    "jummah_times" => jummah_times_from(html),
    "khateeb" => nil,
    "last_verified" => verified_at
  }
  raise "#{record["id"]} has no Jummah iqamah times." if record["jummah_times"].empty?

  validate_record!(record)
  record
end

verified_at = Time.now.utc.iso8601
data = {
  "version" => 1,
  "last_updated" => verified_at,
  "mosques" => MOSQUES.map { |config| build_record(config, verified_at) }
}

File.write(OUTPUT_PATH, "#{JSON.pretty_generate(data)}\n")
puts "Wrote #{OUTPUT_PATH}"
data.fetch("mosques").each do |mosque|
  puts "#{mosque.fetch("short_name")}: #{mosque.fetch("jamaat_times").map { |k, v| "#{k}=#{v}" }.join(", ")}; Jummah #{mosque.fetch("jummah_times").join(", ")}"
end
