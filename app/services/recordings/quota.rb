module Recordings
  class QuotaExceeded < StandardError; end

  # Месячная квота минут распознавания на пользователя (RECORDING_MINUTES_QUOTA, по умолчанию 300)
  module Quota
    module_function

    def limit_minutes = ENV.fetch("RECORDING_MINUTES_QUOTA", 300).to_f

    def used_minutes(user) = UsageEvent.minutes_this_month(user)

    def remaining_minutes(user) = [ limit_minutes - used_minutes(user), 0 ].max

    def check!(user, minutes)
      return if used_minutes(user) + minutes <= limit_minutes
      raise QuotaExceeded,
            "Превышена месячная квота распознавания: осталось #{remaining_minutes(user).floor} из #{limit_minutes.floor} мин, " \
            "а запись длится #{minutes.ceil} мин"
    end

    def record!(user:, recording:, minutes:, cost_usd:)
      UsageEvent.create!(user: user, recording: recording, kind: "transcription",
                         quantity: minutes, unit: "minutes", cost_usd: cost_usd)
    end
  end
end
