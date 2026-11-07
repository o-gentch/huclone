require "test_helper"

class Imports::FiltersTest < ActiveSupport::TestCase
  test "rejects timestamped posts" do
    assert_not Imports::Filters.content_post?("10:30 - встреча с клиентом")
  end

  test "rejects link-only posts" do
    assert_not Imports::Filters.content_post?("Смотрите https://example.com/very/long/link")
  end

  test "accepts prose" do
    assert Imports::Filters.content_post?("Это достаточно длинная строка обычного текста без ссылок и таймкодов.")
  end
end
