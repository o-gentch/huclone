module Ai
  # Обёртка над chat completions для нового кода: логирует токены и оценку стоимости по этапам.
  module Chat
    # USD за 1M токенов (input, output) — только для оценки в логе
    PRICES = {
      "gpt-4o-mini" => [ 0.15, 0.60 ],
      "gpt-4o"      => [ 2.50, 10.00 ]
    }.freeze

    def self.call(stage:, client: Ai::Client.instance, **parameters)
      response = client.chat(parameters: parameters)
      log(stage, parameters[:model], response["usage"])
      response.dig("choices", 0, "message", "content").to_s
    end

    def self.log(stage, model, usage)
      return unless usage

      input, output = usage.values_at("prompt_tokens", "completion_tokens").map(&:to_i)
      in_price, out_price = PRICES.fetch(model, [ 0, 0 ])
      cost = (input * in_price + output * out_price) / 1_000_000.0
      Rails.logger.info("[Ai::Chat] stage=#{stage} model=#{model} in=#{input} out=#{output} cost_usd=#{cost.round(5)}")
    end
  end
end
