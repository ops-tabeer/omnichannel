module Featurable
  extend ActiveSupport::Concern

  MAX_FLAGS_PER_COLUMN = 63

  QUERY_MODE = {
    flag_query_mode: :bit_operator,
    check_for_column: false
  }.freeze

  FEATURE_LIST = YAML.safe_load(Rails.root.join('config/features.yml').read).freeze

  FEATURES_COLUMN_1 = FEATURE_LIST.first(MAX_FLAGS_PER_COLUMN).each_with_object({}) do |feature, result|
    result[result.keys.size + 1] = "feature_#{feature['name']}".to_sym
  end

  FEATURES_COLUMN_2 = FEATURE_LIST.drop(MAX_FLAGS_PER_COLUMN).each_with_object({}) do |feature, result|
    result[result.keys.size + 1] = "feature_#{feature['name']}".to_sym
  end

  COLUMN_2_FLAG_NAMES = FEATURES_COLUMN_2.values.to_set.freeze

  included do
    include FlagShihTzu
    has_flags FEATURES_COLUMN_1.merge(column: 'feature_flags').merge(QUERY_MODE)
    has_flags FEATURES_COLUMN_2.merge(column: 'feature_flags_2').merge(QUERY_MODE) if FEATURES_COLUMN_2.present?

    # Override FlagShihTzu's generated selected_feature_flags= to handle flags split across two columns.
    # The Super Admin form sends all features through selected_feature_flags=,
    # but FlagShihTzu only knows column 1 flags for that setter.
    # We intercept, split by column, and route to the correct setter.
    if FEATURES_COLUMN_2.present?
      col2_names = COLUMN_2_FLAG_NAMES

      define_method(:selected_feature_flags_without_column_2=) do |chosen_flags|
        chosen_flags = Array(chosen_flags).map(&:to_sym).select(&:present?)
        col1_flags = chosen_flags.reject { |f| col2_names.include?(f) }
        col2_flags = chosen_flags.select { |f| col2_names.include?(f) }

        unselect_all_flags('feature_flags')
        col1_flags.each { |flag| enable_flag(flag, 'feature_flags') }

        unselect_all_flags('feature_flags_2')
        col2_flags.each { |flag| enable_flag(flag, 'feature_flags_2') }
      end

      alias_method :selected_feature_flags_original=, :selected_feature_flags=
      alias_method :selected_feature_flags=, :selected_feature_flags_without_column_2=

      # Override reader to include flags from both columns
      define_method(:selected_feature_flags) do
        selected_flags('feature_flags') + selected_flags('feature_flags_2')
      end
    end

    before_create :enable_default_features
  end

  def enable_features(*names)
    names.each do |name|
      send("feature_#{name}=", true)
    end
  end

  def enable_features!(*names)
    enable_features(*names)
    save
  end

  def disable_features(*names)
    names.each do |name|
      send("feature_#{name}=", false)
    end
  end

  def disable_features!(*names)
    disable_features(*names)
    save
  end

  def feature_enabled?(name)
    send("feature_#{name}?")
  end

  def all_features
    FEATURE_LIST.pluck('name').index_with do |feature_name|
      feature_enabled?(feature_name)
    end
  end

  def enabled_features
    all_features.select { |_feature, enabled| enabled == true }
  end

  def disabled_features
    all_features.select { |_feature, enabled| enabled == false }
  end

  private

  def enable_default_features
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return true if config.blank?

    features_to_enabled = config.value.select { |f| f[:enabled] }.pluck(:name)
    enable_features(*features_to_enabled)
  end
end
