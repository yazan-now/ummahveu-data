require "minitest/autorun"
require "tmpdir"

require_relative "../scripts/update_london_masjids"

class UpdateLondonMasjidsTest < Minitest::Test
  def test_london_mosque_official_monthly_page_uses_second_displayed_time
    html = london_mosque_monthly_fixture

    assert_equal(
      {
        "fajr" => "05:00",
        "dhuhr" => "13:50",
        "asr" => "17:45",
        "maghrib" => "20:53",
        "isha" => "22:24"
      },
      london_mosque_official_iqamah_times_from(html, Date.new(2026, 2, 18))
    )
  end

  def test_london_mosque_official_monthly_page_parses_full_month_schedule
    schedule = london_mosque_official_monthly_schedule_from(
      london_mosque_monthly_fixture,
      Date.new(2026, 2, 18)
    )

    assert_equal(28, schedule.length)
    assert_equal("05:15", schedule.fetch("2026-02-01").fetch("fajr"))
    assert_equal("20:53", schedule.fetch("2026-02-18").fetch("maghrib"))
    assert_equal("22:15", schedule.fetch("2026-02-28").fetch("isha"))
  end

  def test_london_mosque_official_monthly_schedule_must_cover_whole_month
    html = <<~HTML
      <table>
        <tbody>
          <tr>
            <td><div>Mon 18</div><div></div></td>
            <td><div>04:20 AM</div><div>05:00 AM</div></td>
            <td style="vertical-align: middle;">05:57 AM</td>
            <td><div>01:22 PM</div><div>01:50 PM</div></td>
            <td><div>05:23 PM</div><div>05:45 PM</div></td>
            <td><div>08:46 PM</div><div>08:53 PM</div></td>
            <td><div>10:14 PM</div><div>10:24 PM</div></td>
          </tr>
        </tbody>
      </table>
    HTML

    error = assert_raises(RuntimeError) do
      london_mosque_official_monthly_schedule_from(html, Date.new(2026, 5, 18))
    end
    assert_match(/missing date/, error.message)
  end

  def test_london_mosque_friday_page_extracts_khutbah_times_once
    html = <<~HTML
      <section>
        <span>First Khutbah 12:00 PM</span>
        <font>Second Khutbah 1:15 PM</font>
        <span>First Khutbah 12:00 PM</span>
      </section>
    HTML

    assert_equal(["12:00", "13:15"], london_mosque_jummah_times_from(html))
  end

  def test_masjidbox_friday_jumuah_card_never_substitutes_for_daily_dhuhr
    html = <<~HTML
      <div class="styles__Item-sc-1h272ay-1 test">
        <div class="title">Fajr</div>
        <div class="time">4:24<sup class="ampm">AM</sup></div>
        <div class="time">5:00<sup class="ampm">AM</sup></div>
      </div>
      <div class="styles__Item-sc-1h272ay-1 test">
        <div class="title">Jumuah 1</div>
        <div class="time">12:00<sup class="ampm">PM</sup></div>
        <div class="time">12:30<sup class="ampm">PM</sup></div>
      </div>
      <div class="styles__Item-sc-1h272ay-1 test">
        <div class="title">Asr</div>
        <div class="time">5:22<sup class="ampm">PM</sup></div>
        <div class="time">5:45<sup class="ampm">PM</sup></div>
      </div>
      <div class="styles__Item-sc-1h272ay-1 test">
        <div class="title">Maghrib</div>
        <div class="time">8:43<sup class="ampm">PM</sup></div>
        <div class="time">8:50<sup class="ampm">PM</sup></div>
      </div>
      <div class="styles__Item-sc-1h272ay-1 test">
        <div class="title">Isha</div>
        <div class="time">10:11<sup class="ampm">PM</sup></div>
        <div class="time">10:21<sup class="ampm">PM</sup></div>
      </div>
      <div class="styles__Wrapper-sc-fn1c8y-0"></div>
    HTML

    error = assert_raises(RuntimeError) { iqamah_times_from(html) }
    assert_match(/Missing iqamah values: dhuhr/, error.message)
  end

  def test_special_prayer_cards_do_not_replace_regular_daily_prayers
    html = <<~HTML
      #{masjidbox_daily_prayer_card("Fajr", "4:24", "5:00", "AM")}
      #{masjidbox_daily_prayer_card("Dhuhr", "1:22", "1:50", "PM")}
      #{masjidbox_daily_prayer_card("Eid Prayer", "7:00", "8:30", "AM")}
      #{masjidbox_daily_prayer_card("Asr", "5:22", "5:45", "PM")}
      #{masjidbox_daily_prayer_card("Maghrib", "8:43", "8:50", "PM")}
      #{masjidbox_daily_prayer_card("Taraweeh", "10:30", "11:00", "PM")}
      #{masjidbox_daily_prayer_card("Isha", "10:11", "10:21", "PM")}
      <div class="styles__Wrapper-sc-fn1c8y-0"></div>
    HTML

    assert_equal(
      {
        "fajr" => "05:00",
        "dhuhr" => "13:50",
        "asr" => "17:45",
        "maghrib" => "20:50",
        "isha" => "22:21"
      },
      iqamah_times_from(html)
    )
  end

  def test_record_validation_rejects_blank_impossible_and_non_chronological_times
    blank = valid_record
    blank["jamaat_times"]["fajr"] = ""
    impossible = valid_record
    impossible["jamaat_times"]["isha"] = "25:00"
    unordered = valid_record
    unordered["jamaat_times"]["asr"] = "12:00"

    assert_raises(RuntimeError) { validate_record!(blank) }
    assert_raises(RuntimeError) { validate_record!(impossible) }
    error = assert_raises(RuntimeError) { validate_record!(unordered) }
    assert_match(/not chronological/, error.message)
  end

  def test_noor_gardens_official_page_verifier_is_fail_closed
    verified_html = <<~HTML
      <h1>MAC Noor Gardens</h1>
      <footer>457 Southdale Rd W, London, ON N6P 1M7</footer>
    HTML
    verify_noor_gardens_metadata!(verified_html)

    error = assert_raises(RuntimeError) do
      verify_noor_gardens_metadata!("<h1>MAC Noor Gardens</h1><footer>London, Ontario</footer>")
    end
    assert_match(/457 Southdale Rd W/, error.message)
    assert_match(/N6P 1M7/, error.message)
  end

  def test_noor_gardens_homepage_parses_current_date_daily_rows_and_jummah
    schedule = noor_gardens_schedule_from(
      noor_gardens_homepage_fixture,
      Date.new(2026, 8, 31)
    )

    assert_equal("2026-08-31", schedule.fetch("date"))
    assert_equal(
      {
        "fajr" => "05:25",
        "dhuhr" => "13:27",
        "asr" => "17:10",
        "maghrib" => "20:05",
        "isha" => "21:27"
      },
      schedule.fetch("athan_times")
    )
    assert_equal(
      {
        "fajr" => "05:56",
        "dhuhr" => "14:00",
        "asr" => "17:30",
        "maghrib" => "20:10",
        "isha" => "21:42"
      },
      schedule.fetch("jamaat_times")
    )
    assert_equal(["12:00", "13:30"], schedule.fetch("jummah_times"))
  end

  def test_noor_gardens_homepage_rejects_stale_or_mismatched_date
    error = assert_raises(RuntimeError) do
      noor_gardens_schedule_from(
        noor_gardens_homepage_fixture(date_text: "August 31, 2020"),
        Date.new(2026, 8, 31)
      )
    end

    assert_match(/displayed date 2020-08-31 does not match 2026-08-31/, error.message)
  end

  def test_noor_gardens_homepage_rejects_missing_or_partial_daily_rows
    missing = noor_gardens_homepage_fixture(prayers: REQUIRED_PRAYER_KEYS - ["isha"])
    partial = noor_gardens_homepage_fixture.sub(
      '<div class="prayer-jamaat">9:42 pm</div>',
      ""
    )

    missing_error = assert_raises(RuntimeError) do
      noor_gardens_schedule_from(missing, Date.new(2026, 8, 31))
    end
    partial_error = assert_raises(RuntimeError) do
      noor_gardens_schedule_from(partial, Date.new(2026, 8, 31))
    end

    assert_match(/exactly one isha row/, missing_error.message)
    assert_match(/isha row must contain one Athan and one Jamaat time/, partial_error.message)
  end

  def test_noor_gardens_homepage_rejects_malformed_times
    malformed = noor_gardens_homepage_fixture.sub("8:10 pm", "8:99 pm")

    error = assert_raises(RuntimeError) do
      noor_gardens_schedule_from(malformed, Date.new(2026, 8, 31))
    end

    assert_match(/minute is invalid/, error.message)
  end

  def test_noor_gardens_homepage_requires_both_jummah_times
    partial = noor_gardens_homepage_fixture(jummah_times: ["12:00 PM"])

    error = assert_raises(RuntimeError) do
      noor_gardens_schedule_from(partial, Date.new(2026, 8, 31))
    end

    assert_match(/exactly one two-prayer Jummah block/, error.message)
  end

  def test_noor_gardens_build_publishes_current_homepage_schedule
    config = noor_gardens_config

    record = stub(:fetch_html, noor_gardens_homepage_fixture) do
      build_record(config, "2026-08-31T20:22:00Z", date: Date.new(2026, 8, 31))
    end

    assert_equal(NOOR_GARDENS_ID, record.fetch("id"))
    assert_equal(NOOR_GARDENS_SOURCE_ID, record.fetch("source_id"))
    assert_equal(noor_gardens_record.fetch("jamaat_times"), record.fetch("jamaat_times"))
    assert_equal(["12:00", "13:30"], record.fetch("jummah_times"))
    refute(record.key?("jummah_status"))
    assert_equal("2026-08-31T20:22:00Z", record.fetch("last_verified"))
    refute(record.key?("jamaat_schedule"))
    validate_record!(record)
  end

  def test_noor_gardens_validation_rejects_incomplete_or_unavailable_current_record
    daily = Marshal.load(Marshal.dump(noor_gardens_record))
    daily["jamaat_times"].delete("isha")
    jummah = Marshal.load(Marshal.dump(noor_gardens_record))
    jummah["jummah_times"] = ["12:00"]
    status = Marshal.load(Marshal.dump(noor_gardens_record))
    status["jummah_status"] = "unavailable"

    assert_raises(RuntimeError) { validate_record!(daily) }
    assert_raises(RuntimeError) { validate_record!(jummah) }
    assert_raises(RuntimeError) { validate_record!(status) }
  end

  def test_record_validation_requires_distinct_ordered_jummah_list
    missing = valid_record
    missing["jummah_times"] = []
    duplicate = valid_record
    duplicate["jummah_times"] = ["12:15", "12:15"]
    unordered = valid_record
    unordered["jummah_times"] = ["13:30", "12:15"]

    assert_raises(RuntimeError) { validate_record!(missing) }
    assert_raises(RuntimeError) { validate_record!(duplicate) }
    assert_raises(RuntimeError) { validate_record!(unordered) }
  end

  def test_stale_fallback_keeps_verified_monthly_day_and_never_claims_new_verification
    date = Date.new(2026, 7, 30)
    prior = valid_record
    prior["jamaat_schedule"] = { date.iso8601 => prior.fetch("jamaat_times").dup }
    previous = { "lmm" => prior }
    fallback = stale_fallback(MOSQUES.first, previous, date: date)

    assert_equal(prior.fetch("jamaat_times"), fallback.fetch("jamaat_times"))
    assert_equal(prior.fetch("last_verified"), fallback.fetch("last_verified"))
    assert_equal(false, fallback.fetch("stale_source"))
  end

  def test_stale_fallback_drops_wrong_day_daily_times_but_keeps_verified_metadata
    date = Date.new(2026, 7, 30)
    prior = valid_record
    previous = { "lmm" => prior }
    fallback = stale_fallback(MOSQUES.first, previous, date: date)

    assert_nil(fallback["jamaat_times"])
    assert_equal(true, fallback.fetch("stale_source"))
    assert_equal(prior.fetch("jummah_times"), fallback.fetch("jummah_times"))
    assert_equal(prior.fetch("last_verified"), fallback.fetch("last_verified"))
    validate_fallback_record!(fallback)
  end

  def test_noor_gardens_last_known_good_remains_unavailable_when_source_fails
    prior = noor_gardens_record
    fallback = stale_fallback(
      noor_gardens_config,
      { NOOR_GARDENS_ID => prior },
      date: Date.new(2026, 8, 27)
    )

    assert_nil(fallback.fetch("jamaat_times"))
    assert_empty(fallback.fetch("jummah_times"))
    assert_equal("unavailable", fallback.fetch("jummah_status"))
    assert_equal(true, fallback.fetch("stale_source"))
    assert_equal(prior.fetch("last_verified"), fallback.fetch("last_verified"))
    validate_fallback_record!(fallback)
  end

  def test_manual_override_is_date_bounded_validated_and_updates_monthly_day()
    date = Date.new(2026, 7, 30)
    record = valid_record
    record["jamaat_schedule"] = { date.iso8601 => record.fetch("jamaat_times").dup }
    override = {
      "mosque_id" => "lmm",
      "starts_on" => date.iso8601,
      "ends_on" => date.iso8601,
      "reason" => "Verified emergency closure schedule",
      "verified_at" => "2026-07-30T14:00:00Z",
      "jamaat_times" => {
        "fajr" => "05:20",
        "dhuhr" => "14:00",
        "asr" => "18:00",
        "maghrib" => "21:00",
        "isha" => "22:30"
      }
    }

    validate_manual_override!(override)
    active = apply_manual_overrides([record], [override], date: date).first
    inactive = apply_manual_overrides([record], [override], date: date.next_day).first

    assert_equal("14:00", active.fetch("jamaat_times").fetch("dhuhr"))
    assert_equal("14:00", active.fetch("jamaat_schedule").fetch(date.iso8601).fetch("dhuhr"))
    assert_equal("2026-07-30T14:00:00Z", active.fetch("last_verified"))
    assert_equal("Verified emergency closure schedule", active.fetch("manual_override").fetch("reason"))
    assert_equal(record, inactive)
  end

  def test_manual_override_rejects_unbounded_or_invalid_schedule()
    invalid = {
      "mosque_id" => "lmm",
      "starts_on" => "2026-07-31",
      "ends_on" => "2026-07-30",
      "reason" => "Invalid",
      "verified_at" => "2026-07-30T14:00:00Z",
      "jamaat_times" => valid_record.fetch("jamaat_times")
    }

    error = assert_raises(RuntimeError) { validate_manual_override!(invalid) }
    assert_match(/ends before/, error.message)
  end

  def test_manual_override_cannot_invent_noor_gardens_schedule
    override = {
      "mosque_id" => NOOR_GARDENS_ID,
      "starts_on" => "2026-08-26",
      "ends_on" => "2026-08-26",
      "reason" => "Unverified schedule",
      "verified_at" => "2026-08-26T16:00:25Z",
      "jummah_times" => ["13:30"]
    }

    error = assert_raises(RuntimeError) { validate_manual_override!(override) }
    assert_match(/uses only its official homepage/, error.message)
  end

  def test_write_data_is_atomic_and_refuses_invalid_dataset()
    data = {
      "version" => 2,
      "last_updated" => "2026-07-30T14:00:00Z",
      "mosques" => MOSQUES.map { |mosque| record_for_config(mosque) }
    }

    Dir.mktmpdir do |directory|
      output = File.join(directory, "london-masjids.json")
      write_data(data, output_path: output)
      assert_equal(data, JSON.parse(File.read(output)))

      invalid = Marshal.load(Marshal.dump(data))
      invalid.fetch("mosques").first.fetch("jamaat_times")["asr"] = ""
      assert_raises(RuntimeError) { write_data(invalid, output_path: output) }
      assert_equal(data, JSON.parse(File.read(output)))
    end
  end

  private

  def noor_gardens_config
    MOSQUES.find { |mosque| mosque.fetch(:id) == NOOR_GARDENS_ID }
  end

  def noor_gardens_record
    config = noor_gardens_config
    {
      "id" => config.fetch(:id),
      "name" => config.fetch(:name),
      "short_name" => config.fetch(:short_name),
      "address" => config.fetch(:address),
      "lat" => config.fetch(:lat),
      "lng" => config.fetch(:lng),
      "phone" => config.fetch(:phone),
      "logo_url" => nil,
      "data_source" => "official_website",
      "source_url" => config.fetch(:source_url),
      "source_id" => config.fetch(:source_id),
      "jamaat_times" => {
        "fajr" => "05:56",
        "dhuhr" => "14:00",
        "asr" => "17:30",
        "maghrib" => "20:10",
        "isha" => "21:42"
      },
      "jummah_times" => ["12:00", "13:30"],
      "khateeb" => nil,
      "last_verified" => "2026-08-31T20:22:00Z"
    }
  end

  def record_for_config(config)
    return noor_gardens_record if config.fetch(:id) == NOOR_GARDENS_ID

    valid_record.merge(
      "id" => config.fetch(:id),
      "name" => config.fetch(:name),
      "short_name" => config.fetch(:short_name),
      "address" => config.fetch(:address),
      "source_url" => config.fetch(:source_url),
      "data_source" => config.fetch(:source_type) == "masjidbox" ? "masjidbox" : "official_website"
    )
  end

  def valid_record
    {
      "id" => "lmm",
      "name" => "London Muslim Mosque",
      "short_name" => "LMM",
      "address" => "151 Oxford St W, London, ON N6H 1S1",
      "lat" => 42.9849,
      "lng" => -81.2453,
      "phone" => "+1-519-439-9451",
      "logo_url" => nil,
      "data_source" => "official_website",
      "source_url" => "https://www.londonmosque.ca/page/pray_time/monthly/2026-07",
      "source_id" => nil,
      "jamaat_times" => {
        "fajr" => "05:15",
        "dhuhr" => "13:50",
        "asr" => "17:45",
        "maghrib" => "20:56",
        "isha" => "22:19"
      },
      "jummah_times" => ["12:00", "13:15"],
      "khateeb" => nil,
      "last_verified" => "2026-07-30T09:11:54Z"
    }
  end

  def masjidbox_daily_prayer_card(title, athan, iqamah, period)
    <<~HTML
      <div class="styles__Item-sc-1h272ay-1 test">
        <div class="title">#{title}</div>
        <div class="time">#{athan}<sup class="ampm">#{period}</sup></div>
        <div class="time">#{iqamah}<sup class="ampm">#{period}</sup></div>
      </div>
    HTML
  end

  def noor_gardens_homepage_fixture(
    date_text: "August 31, 2026",
    prayers: REQUIRED_PRAYER_KEYS,
    jummah_times: ["12:00 PM", "1:30 PM"]
  )
    athan = {
      "fajr" => "5:25 am",
      "dhuhr" => "1:27 pm",
      "asr" => "5:10 pm",
      "maghrib" => "8:05 pm",
      "isha" => "9:27 pm"
    }
    jamaat = {
      "fajr" => "5:56 am",
      "dhuhr" => "2:00 pm",
      "asr" => "5:30 pm",
      "maghrib" => "8:10 pm",
      "isha" => "9:42 pm"
    }
    cards = prayers.map do |key|
      <<~HTML
        <div class="prayer-time prayer-#{key} ">
          <h3>#{key}</h3>
          <div class="prayer-start">#{athan.fetch(key)}</div>
          <div class="prayer-jamaat">#{jamaat.fetch(key)}</div>
        </div> <!-- END of prayer time-->
      HTML
    end.join
    jummah = if jummah_times.length == 2
                <<~HTML
                  <h2 class="elementor-heading-title elementor-size-default">
                    Prayer 1: #{jummah_times[0]} <br>Prayer 2: #{jummah_times[1]}
                  </h2>
                HTML
              else
                "<h2>Prayer 1: #{jummah_times.first}</h2>"
              end

    <<~HTML
      <title>MAC Noor Gardens</title>
      <div class="dpt-horizontal-wrapper customStyles">
        <div class="dpt-heading"><h3 class="date side-by-side">#{date_text}</h3></div>
        <div class="dpt-wrapper-container">
          #{cards}
        </div> <!-- END of wrapper container-->
      </div>
      <h2>Jummah</h2>
      #{jummah}
      <footer>457 Southdale Rd W, London, ON N6P 1M7</footer>
    HTML
  end

  def london_mosque_monthly_fixture
    rows = (1..28).map do |day|
      fajr_jamaat = day == 1 ? "05:15 AM" : "05:00 AM"
      maghrib_jamaat = day == 18 ? "08:53 PM" : "08:34 PM"
      isha_jamaat = day == 28 ? "10:15 PM" : "10:24 PM"
      <<~HTML
        <tr>
          <td><div>#{day.to_s.rjust(2, "0")}</div><div></div></td>
          <td><div>04:20 AM</div><div>#{fajr_jamaat}</div></td>
          <td style="vertical-align: middle;">05:57 AM</td>
          <td><div>01:22 PM</div><div>01:50 PM</div></td>
          <td><div>05:23 PM</div><div>05:45 PM</div></td>
          <td><div>08:46 PM</div><div>#{maghrib_jamaat}</div></td>
          <td><div>10:14 PM</div><div>#{isha_jamaat}</div></td>
        </tr>
      HTML
    end
    "<table><tbody>#{rows.join}</tbody></table>"
  end
end
