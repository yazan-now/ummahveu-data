require "minitest/autorun"

require_relative "../scripts/update_london_masjids"

class UpdateLondonMasjidsTest < Minitest::Test
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
end
