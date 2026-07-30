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

  def test_write_data_is_atomic_and_refuses_invalid_dataset()
    data = {
      "version" => 2,
      "last_updated" => "2026-07-30T14:00:00Z",
      "mosques" => MOSQUES.map do |mosque|
        valid_record.merge(
          "id" => mosque.fetch(:id),
          "name" => mosque.fetch(:name),
          "short_name" => mosque.fetch(:short_name),
          "address" => mosque.fetch(:address),
          "source_url" => mosque.fetch(:source_url)
        )
      end
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
