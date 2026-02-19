# frozen_string_literal: true

module ParadeDB
  # Typed helpers for building agg JSON payloads passed to pdb.agg(...).
  module Aggregations
    TERMS_ORDER = {
      "-count" => { "_count" => "desc" },
      "count" => { "_count" => "asc" },
      "-key" => { "_key" => "desc" },
      "key" => { "_key" => "asc" }
    }.freeze

    module_function

    def build_named_payload(named_aggregations)
      specs = named_aggregations.to_h
      raise ArgumentError, "with_agg/facets_agg requires at least one named aggregation" if specs.empty?

      specs.each_with_object({}) do |(alias_name, spec), payload|
        alias_key = normalize_alias(alias_name)
        payload[alias_key] = normalize_spec(spec)
      end
    end

    def terms(field, size: 10, order: "-count", missing: nil)
      terms_payload = { "field" => normalize_field(field) }
      terms_payload["size"] = normalize_non_negative_integer(size, "size") unless size.nil?
      terms_payload["order"] = normalize_terms_order(order) unless order.nil?
      terms_payload["missing"] = missing unless missing.nil?
      { "terms" => terms_payload }
    end

    def value_count(field)
      metric("value_count", field)
    end

    def avg(field)
      metric("avg", field)
    end

    def sum(field)
      metric("sum", field)
    end

    def min(field)
      metric("min", field)
    end

    def max(field)
      metric("max", field)
    end

    def stats(field)
      metric("stats", field)
    end

    def percentiles(field, percents:)
      values = Array(percents)
      raise ArgumentError, "percents must include at least one value" if values.empty?

      { "percentiles" => { "field" => normalize_field(field), "percents" => values } }
    end

    def histogram(field, interval:, min_doc_count: nil, offset: nil, hard_bounds: nil, extended_bounds: nil)
      raise ArgumentError, "interval is required" if interval.nil?

      payload = {
        "field" => normalize_field(field),
        "interval" => interval
      }
      payload["min_doc_count"] = normalize_non_negative_integer(min_doc_count, "min_doc_count") unless min_doc_count.nil?
      payload["offset"] = offset unless offset.nil?
      payload["hard_bounds"] = normalize_bounds(hard_bounds, "hard_bounds") unless hard_bounds.nil?
      payload["extended_bounds"] = normalize_bounds(extended_bounds, "extended_bounds") unless extended_bounds.nil?
      { "histogram" => payload }
    end

    def date_histogram(
      field,
      calendar_interval: nil,
      fixed_interval: nil,
      interval: nil,
      min_doc_count: nil,
      offset: nil,
      time_zone: nil,
      format: nil,
      hard_bounds: nil,
      extended_bounds: nil
    )
      interval_args = {
        "calendar_interval" => calendar_interval,
        "fixed_interval" => fixed_interval,
        "interval" => interval
      }.compact

      if interval_args.empty?
        raise ArgumentError, "date_histogram requires one of: calendar_interval, fixed_interval, interval"
      end

      if interval_args.length > 1
        raise ArgumentError, "date_histogram interval arguments are mutually exclusive"
      end

      payload = { "field" => normalize_field(field) }.merge(interval_args)
      payload["min_doc_count"] = normalize_non_negative_integer(min_doc_count, "min_doc_count") unless min_doc_count.nil?
      payload["offset"] = offset unless offset.nil?
      payload["time_zone"] = time_zone unless time_zone.nil?
      payload["format"] = format unless format.nil?
      payload["hard_bounds"] = normalize_bounds(hard_bounds, "hard_bounds") unless hard_bounds.nil?
      payload["extended_bounds"] = normalize_bounds(extended_bounds, "extended_bounds") unless extended_bounds.nil?
      { "date_histogram" => payload }
    end

    def range(field, ranges:)
      serialized_ranges = Array(ranges).map do |entry|
        raise ArgumentError, "range entries must be Hash values" unless entry.is_a?(Hash)

        normalized = deep_stringify(entry)
        unless normalized.key?("from") || normalized.key?("to")
          raise ArgumentError, "range entries require at least one of: from, to"
        end

        normalized
      end
      raise ArgumentError, "ranges must include at least one entry" if serialized_ranges.empty?

      {
        "range" => {
          "field" => normalize_field(field),
          "ranges" => serialized_ranges
        }
      }
    end

    def metric(name, field)
      { name => { "field" => normalize_field(field) } }
    end
    private_class_method :metric

    def normalize_alias(alias_name)
      value =
        case alias_name
        when Symbol then alias_name.to_s
        when String then alias_name
        else
          raise ArgumentError, "Aggregation names must be symbols or strings, got #{alias_name.class}"
        end
      raise ArgumentError, "Aggregation names cannot be empty" if value.strip.empty?

      value
    end
    private_class_method :normalize_alias

    def normalize_spec(spec)
      case spec
      when Hash
        normalized = deep_stringify(spec)
        raise ArgumentError, "Aggregation specs cannot be empty" if normalized.empty?
        unless normalized.size == 1
          raise ArgumentError, "Aggregation specs must have exactly one top-level key"
        end
        normalized
      else
        raise ArgumentError, "Aggregation specs must be Hash values, got #{spec.class}"
      end
    end
    private_class_method :normalize_spec

    def normalize_field(field)
      case field
      when Symbol
        field.to_s
      when String
        raise ArgumentError, "field cannot be empty" if field.strip.empty?
        field
      else
        raise ArgumentError, "field must be a Symbol or String, got #{field.class}"
      end
    end
    private_class_method :normalize_field

    def normalize_terms_order(order)
      mapped = TERMS_ORDER[order]
      return mapped if mapped

      valid = TERMS_ORDER.keys.map(&:inspect).join(", ")
      raise ArgumentError, "Unknown terms order #{order.inspect}. Valid values: #{valid}"
    end
    private_class_method :normalize_terms_order

    def normalize_non_negative_integer(value, name)
      normalized = Integer(value)
      raise ArgumentError, "#{name} must be an integer greater than or equal to 0" if normalized.negative?

      normalized
    rescue ArgumentError, TypeError
      raise ArgumentError, "#{name} must be an integer greater than or equal to 0"
    end
    private_class_method :normalize_non_negative_integer

    def normalize_bounds(bounds, name)
      raise ArgumentError, "#{name} must be a Hash with 'min'/'max' keys" unless bounds.is_a?(Hash)

      normalized = deep_stringify(bounds)
      unless normalized.key?("min") || normalized.key?("max")
        raise ArgumentError, "#{name} must include at least one of: min, max"
      end

      normalized
    end
    private_class_method :normalize_bounds

    def deep_stringify(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, child), out| out[key.to_s] = deep_stringify(child) }
      when Array
        value.map { |child| deep_stringify(child) }
      else
        value
      end
    end
    private_class_method :deep_stringify
  end
end
