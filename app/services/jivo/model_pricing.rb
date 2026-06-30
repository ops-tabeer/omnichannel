module Jivo::ModelPricing
  # Approximate OpenAI list prices in USD per 1,000,000 tokens. Update as pricing changes.
  # Reused for any JIVO AI cost estimate (idle follow-up now; main bot later).
  PRICES = {
    'gpt-4.1' => { input: 2.00, output: 8.00 },
    'gpt-4.1-mini' => { input: 0.40, output: 1.60 },
    'gpt-4.1-nano' => { input: 0.10, output: 0.40 },
    'gpt-4o' => { input: 2.50, output: 10.00 },
    'gpt-4o-mini' => { input: 0.15, output: 0.60 }
  }.freeze

  DEFAULT_PRICE = { input: 0.40, output: 1.60 }.freeze

  def self.price_for(model)
    PRICES[model.to_s] || DEFAULT_PRICE
  end

  # Estimated USD cost for the given model and token counts.
  def self.cost(model:, input_tokens:, output_tokens:)
    price = price_for(model)
    ((input_tokens * price[:input]) + (output_tokens * price[:output])) / 1_000_000.0
  end
end
