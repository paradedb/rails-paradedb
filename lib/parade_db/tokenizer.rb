class Tokenizer
  attr_reader :name, :positional_args, :options

  def initialize(name, positional_args, options)
    @name = name
    @positional_args = positional_args
    @options = options
  end

  def render()
    if options.nil? && positional_args.nil?
      return "pdb.#{name}"
    end

    args = []
    if !positional_args.nil?
      args.concat(positional_args.map { |x| render_positional_arg(x) })
    end
    if !options.nil?
      args.concat(options.map {|k, v| quote_term("#{k}=#{v}")})
    end

    return "pdb.#{name}(#{args.join(",")})"
  end

  def self.whitespace(options: nil)
    new("whitespace", nil, options)
  end

  def self.unicode_words(options: nil)
    new("unicode_words", nil, options)
  end

  def self.ngram(min_gram, max_gram, options: nil)
    new("ngram", [min_gram, max_gram], options)
  end

  def self.simple(options: nil)
    new("simple", nil, options)
  end

  def self.literal(options: nil)
    new("literal", nil, options)
  end

  def self.literal_normalized(options: nil)
    new("literal_normalized", nil, options)
  end

  def self.edge_ngram(min_gram, max_gram, options: nil)
    new("edge_ngram", [min_gram, max_gram], options)
  end

  def self.regex_pattern(pattern, options: nil)
    new("regex_pattern", [pattern], options)
  end

  def self.chinese_compatible(options: nil)
    new("chinese_compatible", nil, options)
  end

  def self.lindera(dictionary, options: nil)
    new("lindera", [dictionary], options)
  end

  def self.icu(options: nil)
    new("icu", nil, options)
  end

  def self.jieba(options: nil)
    new("jieba", nil, options)
  end

  def self.source_code(options: nil)
    new("source_code", nil, options)
  end

  private

  def quote_term(value)
    escaped = value.gsub("'", "''")
    "'#{escaped}'"
  end

  def render_positional_arg(value)
    case value
    when true, false, Numeric
      value.to_s
    when String
      quote_term(value)
    else
      raise InvalidArgumentError, "Unsupported tokenizer arg type: #{value.class}"
    end
  end
end
