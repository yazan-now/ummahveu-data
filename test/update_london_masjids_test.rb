require "minitest/autorun"

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

  def test_masjidbox_friday_jumuah_card_supplies_dhuhr
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

    assert_equal(
      {
        "fajr" => "05:00",
        "dhuhr" => "12:30",
        "asr" => "17:45",
        "maghrib" => "20:50",
        "isha" => "22:21"
      },
      iqamah_times_from(html)
    )
  end

  private

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
