#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "pathname"
require "set"

ROOT = Pathname(__dir__).join("..").expand_path
API_JSON = ROOT.join("api.json")
APIIGNORE_JSON = ROOT.join("apiignore.json")
TOKENIZER_TYPE_KEY_PREFIX = "PDB_TYPE_TOKENIZER_"

def load_json(path)
  JSON.parse(path.read)
rescue Errno::ENOENT
  raise "#{path} not found"
rescue JSON::ParserError => e
  raise "invalid JSON in #{path}: #{e.message}"
end

def flatten_ignore(section, kind:)
  case section
  when nil
    Set.new
  when Array
    Set.new(section.map(&:to_s))
  when Hash
    Set.new(section.values.flatten.map(&:to_s))
  else
    raise "apiignore #{kind} section must be an Array or object of Arrays"
  end
end

def source_paths
  files = Dir.glob(ROOT.join("lib/**/*.rb").to_s).sort
  rakefile = ROOT.join("Rakefile")
  files << rakefile.to_s if rakefile.file?
  files
end

def read_sources
  source_paths.to_h { |path| [path, File.read(path)] }
end

def missing_quoted_tokens(expected_tokens, source_text)
  expected_tokens.select do |token|
    !source_text.match?(/["']#{Regexp.escape(token)}["']/)
  end.sort
end

def missing_symbols(expected_symbols, source_text)
  expected_symbols.select { |symbol| !source_text.include?(symbol) }.sort
end

def main
  api = load_json(API_JSON)
  apiignore = APIIGNORE_JSON.file? ? load_json(APIIGNORE_JSON) : {}

  operators = Set.new(api.fetch("operators").values.map(&:to_s))
  functions = Set.new(api.fetch("functions").values.map(&:to_s))
  all_types_by_key = api.fetch("types").transform_keys(&:to_s).transform_values(&:to_s)

  tokenizer_types = Set.new(
    all_types_by_key
      .select { |name, _| name.start_with?(TOKENIZER_TYPE_KEY_PREFIX) }
      .values
  )
  static_types = Set.new(
    all_types_by_key
      .reject { |name, _| name.start_with?(TOKENIZER_TYPE_KEY_PREFIX) }
      .values
  )

  ignored_operators = flatten_ignore(apiignore["operators"], kind: "operators")
  ignored_functions = flatten_ignore(apiignore["functions"], kind: "functions")
  ignored_types = flatten_ignore(apiignore["types"], kind: "types")

  sources = read_sources
  source_text = sources.values.join("\n")

  missing_ops = missing_quoted_tokens(operators, source_text)
  missing_functions = missing_symbols(functions, source_text)
  missing_static_types = missing_symbols(static_types, source_text)

  tokenizer_sql = sources.find { |path, _| path.end_with?("lib/parade_db/tokenizer_sql.rb") }&.last.to_s
  dynamic_tokenizer_supported = tokenizer_sql.include?('"pdb.#{function_name}"')
  missing_tokenizer_types = dynamic_tokenizer_supported ? [] : tokenizer_types.to_a.sort

  referenced_symbols = Set.new(source_text.scan(/\bpdb\.[a-zA-Z_][a-zA-Z0-9_]*\b/))
  allowed_symbols = functions | static_types | tokenizer_types | ignored_functions | ignored_types
  untracked_symbols = (referenced_symbols - allowed_symbols).to_a.sort

  issues = []

  unless missing_ops.empty?
    issues << "operators declared in api.json but not found in Ruby wrappers: #{missing_ops.join(', ')}"
  end

  unless missing_functions.empty?
    issues << "functions declared in api.json but not found in Ruby wrappers: #{missing_functions.join(', ')}"
  end

  unless missing_static_types.empty?
    issues << "types declared in api.json but not found in Ruby wrappers: #{missing_static_types.join(', ')}"
  end

  unless missing_tokenizer_types.empty?
    issues << "tokenizer types require dynamic tokenizer qualification, but support was not detected: #{missing_tokenizer_types.join(', ')}"
  end

  unless untracked_symbols.empty?
    issues << "pdb.* symbols used in code but missing from api.json/apiignore.json: #{untracked_symbols.join(', ')}"
  end

  if issues.empty?
    puts "✅ API coverage check passed."
    puts "   operators: #{operators.size}, functions: #{functions.size}, types: #{all_types_by_key.size}, referenced symbols: #{referenced_symbols.size}"
    return 0
  end

  warn "❌ API coverage check failed:"
  issues.each { |issue| warn "   - #{issue}" }
  warn "\nUpdate api.json, apiignore.json, or wrapper usage so they stay in sync."
  1
end

exit(main)
